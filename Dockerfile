# Build container tools
FROM ubuntu:20.04 AS container-tools
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update; \
	apt-get install -y \
		git \
		libassuan-dev \
		libbtrfs-dev \
		libdevmapper-dev \
		libgpgme-dev \
		make \
		pkg-config \
		wget

RUN wget -P /tmp https://go.dev/dl/go1.21.0.linux-amd64.tar.gz && \
	tar -C /usr/local -xzf /tmp/go1.21.0.linux-amd64.tar.gz
ENV PATH /usr/local/go/bin:$PATH

# Build skopeo
RUN git clone https://github.com/containers/skopeo.git /skopeo && \
	cd /skopeo && git checkout -q v1.13.2 && \
	GO_DYN_FLAGS= CGO_ENABLED=0 BUILDTAGS=containers_image_openpgp DISABLE_DOCS=1 make

# Build ostreeuploader, aka fiopush/fiocheck
FROM ubuntu:20.04 AS fiotools
RUN apt-get update
RUN apt-get install -y wget git gcc make
RUN wget -P /tmp https://go.dev/dl/go1.21.0.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf /tmp/go1.21.0.linux-amd64.tar.gz
ENV PATH /usr/local/go/bin:$PATH

RUN git clone https://github.com/foundriesio/ostreeuploader.git /ostreeuploader && \
    cd /ostreeuploader && git checkout -q 2022.4 && \
    cd /ostreeuploader && make


FROM buildpack-deps:20.04

# bitbake requires a utf8 filesystem encoding
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG DEBIAN_FRONTEND=noninteractive
ARG DEV_USER_NAME=Builder
ARG DEV_USER=builder
ARG DEV_USER_PASSWD=builder

# FIO PPA for additional dependencies and newer packages
RUN apt-get update; \
	apt-get install -y --no-install-recommends software-properties-common; \
	add-apt-repository ppa:fio-maintainers/ppa; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/*

RUN apt-get update; \
	apt-get install -y --no-install-recommends \
		android-sdk-ext4-utils \
		android-sdk-libsparse-utils \
		awscli \
		ca-certificates \
		chrpath \
		corkscrew \
		cpio \
		curl \
		debianutils \
		device-tree-compiler \
		diffstat \
		docker-compose \
		file \
		g++ \
		gawk \
		git-lfs \
		gnupg \
		iproute2 \
		iputils-ping \
		less \
		libc6-dev-i386 \
		libegl1-mesa \
		libelf-dev \
		liblz4-tool \
		libmagickwand-dev \
		libmath-prime-util-perl \
		libncurses-dev \
		libsdl1.2-dev \
		libsdl1.2-dev \
		libssl-dev \
		libtinfo5 \
		locales nano \
		lz4 \
		make \
		mesa-common-dev \
		openjdk-11-jre \
		openssh-client \
		patch \
		perl-modules \
		python3 \
		python3-dev \
		python3-jinja2 \
		python3-pip \
		python3-requests \
		repo \
		screen \
		socket \
		sudo \
		tcl \
		texinfo \
		tmux \
		vim \
		vim-tiny \
		wget \
		whiptail \
		xz-utils \
		zstd \
	; \
	ln -s /usr/bin/python3 /usr/bin/python; \
	pip3 --no-cache-dir install expandvars jsonFormatter; \
	apt-get autoremove -y; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/*; \
	locale-gen en_US.UTF-8

# Create the user which will run the SDK binaries.
RUN useradd -c $DEV_USER_NAME \
	-d /home/$DEV_USER \
	-G sudo,dialout,floppy,plugdev,users \
	-m \
	-s /bin/bash \
	$DEV_USER

# Add default password for the SDK user (useful with sudo)
RUN echo $DEV_USER:$DEV_USER_PASSWD | chpasswd

# Initialize development environment for $DEV_USER.
RUN sudo -u $DEV_USER -H git config --global credential.helper 'cache --timeout=3600'

# Install ostreeuploader, aka fiopush/fiocheck
COPY --from=fiotools /ostreeuploader/bin/fiopush /usr/bin/
COPY --from=fiotools /ostreeuploader/bin/fiocheck /usr/bin/
ENV FIO_PUSH_CMD /usr/bin/fiopush
ENV FIO_CHECK_CMD /usr/bin/fiocheck

# Install skopeo
COPY --from=container-tools /skopeo/bin/skopeo /usr/bin

# Install docker CLI, required by the oe-builtin App preload
RUN mkdir -p /etc/apt/keyrings \
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null; \
	apt-get update; \
	apt-get install -y \
		containerd.io \
		docker-buildx-plugin \
		docker-ce-cli \
		docker-compose-plugin \
	; \
	apt-get clean; \
	rm -rf /var/lib/apt/lists/*
