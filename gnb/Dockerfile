# Base image
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    cmake \
    g++ \
    libfftw3-dev \
    libsctp-dev \
    libzmq3-dev \
    libuhd-dev \
    git \
    && apt-get clean

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Clone the srsRAN project
RUN git clone https://github.com/srsran/srsRAN_Project.git /srsRAN_Project

# Build the project
WORKDIR /srsRAN_Project
RUN mkdir build && cd build && \
    cmake .. && \
    make -j$(nproc)

# Set up the gNB entrypoint
WORKDIR /srsRAN_Project/build
ENTRYPOINT ["./gnb"]