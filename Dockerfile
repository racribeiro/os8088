FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        make \
        nasm \
        python3 \
        qemu-system-x86 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . .

RUN chmod +x docker/run-qemu.sh

EXPOSE 5900

CMD ["./docker/run-qemu.sh"]
