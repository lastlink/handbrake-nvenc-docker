FROM debian:10 AS builder


MAINTAINER zocker-160

ENV HANDBRAKE_VERSION 1.3.3
ENV HANDBRAKE_VERSION_BRANCH 1.3.x
ENV HANDBRAKE_DEBUG_MODE none

ENV HANDBRAKE_URL https://api.github.com/repos/HandBrake/HandBrake/releases/tags/$HANDBRAKE_VERSION
ENV HANDBRAKE_URL_GIT https://github.com/HandBrake/HandBrake.git

ENV DEBIAN_FRONTEND noninteractive


WORKDIR /HB

# Compile HandBrake
RUN apt-get update
RUN apt-get install -y \
	jq dtrx curl diffutils wget file coreutils m4 xz-utils nasm python3 python3-pip

# Install dependencies
RUN apt-get install -y \
	autoconf automake build-essential cmake git libass-dev libbz2-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libvorbis-dev libx264-dev libxml2-dev libvpx-dev m4 make ninja-build patch pkg-config python tar zlib1g-dev

#RUN apt-get install -y \
#	autoconf automake autopoint build-essential cmake git libass-dev libbz2-dev libfontconfig1-dev libfreetype6-dev libfribidi-dev libharfbuzz-dev libjansson-dev liblzma-dev libmp3lame-dev libnuma-dev libogg-dev libopus-dev libsamplerate-dev libspeex-dev libtheora-dev libtool libtool-bin libvorbis-dev libx264-dev libxml2-dev libvpx-dev m4 make nasm ninja-build patch pkg-config python tar zlib1g-dev
    
# Intel CSV dependencies
RUN apt-get install -y libva-dev libdrm-dev
    
# GTK GUI dependencies
RUN apt-get install -y \
	intltool libappindicator-dev libdbus-glib-1-dev libglib2.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgtk-3-dev libgudev-1.0-dev libnotify-dev libwebkit2gtk-4.0-dev

# install meson from pip
RUN pip3 install meson


# Download HandBrake sources
RUN echo "Downloading HandBrake sources..."
# RUN curl --silent $HANDBRAKE_URL | jq -r '.assets[0].browser_download_url' | wget -i - -O "HandBrake-source.tar.bz2"
RUN git clone $HANDBRAKE_URL_GIT
# RUN dtrx -n HandBrake-source.tar.bz2
# RUN rm -rf HandBrake-source.tar.bz2
# Download patches
# RUN echo "Downloading patches..."
# RUN curl --progress-bar -L -o /HB/HandBrake-source/HandBrake-$HANDBRAKE_VERSION/A00-hb-video-preset.patch https://raw.githubusercontent.com/jlesage/docker-handbrake/master/A00-hb-video-preset.patch

# Compile HandBrake
# WORKDIR /HB/HandBrake-source/HandBrake-$HANDBRAKE_VERSION_BRANCH
WORKDIR /HB/HandBrake

RUN git checkout $HANDBRAKE_VERSION_BRANCH
RUN ./scripts/repo-info.sh > version.txt

RUN echo "Compiling HandBrake..."
RUN ./configure --prefix=/usr/local \
                --debug=$HANDBRAKE_DEBUG_MODE \
                --disable-gtk-update-checks \
                --enable-fdk-aac \
                --enable-x265 \
                --launch-jobs=$(nproc) \
                --launch

RUN make -j$(nproc) --directory=build install

##################################################
# Pull base image
FROM jlesage/baseimage-gui:debian-10

ENV DEBIAN_FRONTEND noninteractive
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES all

ENV APP_NAME="HandBrake"
ENV AUTOMATED_CONVERSION_PRESET="Very Fast 1080p30"
ENV AUTOMATED_CONVERSION_FORMAT="mp4"
# URLs
ENV APP_ICON_URL https://raw.githubusercontent.com/jlesage/docker-templates/master/jlesage/images/handbrake-icon.png
ENV DVDCSS_URL http://www.deb-multimedia.org/pool/main/libd/libdvdcss/libdvdcss2_1.4.2-dmo1_amd64.deb


WORKDIR /tmp

# Install dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
        # For optical drive listing:
        lsscsi \
        # For watchfolder
        bash \
        coreutils \
        yad \
        findutils \
        expect \
        tcl8.6 \
        wget
        
# Handbrake dependencies
RUN apt-get install -y \
	libcairo2 libgtk-3-0 libgudev-1.0-0 libjansson4 libnotify4 libtheora0 libvorbis0a libvorbisenc2 speex libopus0 libxml2 numactl xz-utils git libdbus-glib-1-2 lame x264 libass9
# Handbrake GUI dependencies
#RUN apt-get install -y \
#	intltool libappindicator3-1 libdbus-glib-1-dev libglib2.0-dev libgstreamer1.0 libgstreamer-plugins-base1.0
RUN apt-get install -y \
	libgstreamer-plugins-base1.0


# To read encrypted DVDs
RUN wget $DVDCSS_URL
RUN apt install -y ./libdvdcss2_1.4.2-dmo1_amd64.deb
# install scripts and stuff from upstream Handbrake docker image
RUN git config --global http.sslVerify false
RUN git clone https://github.com/jlesage/docker-handbrake.git
RUN cp -r docker-handbrake/rootfs/* /
# Cleanup
RUN apt-get remove wget git -y && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    apt-get clean -y && \
    apt-get purge -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Adjust the openbox config
RUN \
    # Maximize only the main/initial window.
    sed-patch 's/<application type="normal">/<application type="normal" title="HandBrake">/' \
        /etc/xdg/openbox/rc.xml && \
    # Make sure the main window is always in the background.
    sed-patch '/<application type="normal" title="HandBrake">/a \    <layer>below</layer>' \
        /etc/xdg/openbox/rc.xml

# Generate and install favicons
RUN \
    apt-get update && \
	install_app_icon.sh "$APP_ICON_URL" && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    apt-get clean -y && \
    apt-get purge -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy HandBrake from base build image
COPY --from=builder /usr/local /usr

# Define mountable directories
VOLUME ["/config"]
VOLUME ["/storage"]
VOLUME ["/output"]
VOLUME ["/watch"]
