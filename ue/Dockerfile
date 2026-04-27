FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Build deps (may be trimmed for faster builds)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git wget ca-certificates python3 python3-pip \
    libzmq3-dev pkg-config libssl-dev libfftw3-dev libreadline-dev libncurses5-dev \
    libboost-all-dev libgmp-dev libusb-1.0-0-dev automake autoconf libtool \
    autotools-dev libsoapysdr-dev soapyremote-server socat && \
  rm -rf /var/lib/apt/lists/*

# Optional: adjust as needed for exact upstream repo
WORKDIR /opt
RUN git clone --depth 1 https://github.com/srsran/srsRAN_4G.git srsRAN_4G || true

WORKDIR /opt/srsRAN_4G
RUN mkdir -p build && cd build && cmake .. && make -j$(nproc) || true

# Keep srsue binary path consistent with scripts
RUN mkdir -p /opt/srsRAN_4G/build/srsue/src || true
# if the build succeeded, the binary will be here

# Add helper scripts
COPY entrypoint.sh /srsue/entrypoint.sh
RUN chmod +x /srsue/entrypoint.sh

# Minimal runtime
CMD ["/srsue/entrypoint.sh"]
