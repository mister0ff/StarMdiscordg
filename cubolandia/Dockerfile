# Servidor dedicado da Cubolândia (24h). Uso:
#   docker build -t cubolandia-server .
#   docker run -d --restart unless-stopped -p 25565:25565/udp -v cubo-data:/data cubolandia-server
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip ca-certificates libfontconfig1 libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 && rm -rf /var/lib/apt/lists/*
ARG GODOT=4.3-stable
RUN wget -q https://github.com/godotengine/godot/releases/download/${GODOT}/Godot_v${GODOT}_linux.x86_64.zip -O /tmp/g.zip \
 && unzip -q /tmp/g.zip -d /opt && mv /opt/Godot_v${GODOT}_linux.x86_64 /usr/local/bin/godot && chmod +x /usr/local/bin/godot && rm /tmp/g.zip
WORKDIR /app
COPY . /app
RUN godot --headless --path /app --import || true
ENV XDG_DATA_HOME=/data CUBO_SERVER=1 CUBO_PORT=25565
VOLUME /data
EXPOSE 25565/udp 25565/tcp
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
