#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Bedrock Host - painel de controle para o Minecraft Bedrock Dedicated Server (BDS).

* So usa a biblioteca padrao do Python (3.8+). Nao precisa de pip.
* Liga/desliga/reinicia o servidor, console ao vivo, logs com rotacao,
  gerenciador de arquivos, backups a quente, addons, watchdog 24/7,
  atualizacao do BDS e tunel opcional (playit.gg).

Uso:
    python3 panel.py                       # inicia o painel
    python3 panel.py --set-password SENHA  # define/troca a senha
    python3 panel.py --print-password      # mostra a senha inicial gerada
    python3 panel.py --install             # baixa/instala a ultima versao do BDS
    python3 panel.py --install --version 1.21.50.07
    python3 panel.py --install-tunnel      # baixa o agente playit.gg
"""
from __future__ import annotations

import collections
import hashlib
import hmac
import http.cookies
import http.server
import json
import logging
import logging.handlers
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
DATA = Path(os.environ.get("BEDROCK_DATA", "/srv/bedrock")).resolve()
SERVER_DIR = DATA / "server"
BACKUP_DIR = DATA / "backups"
LOG_DIR = DATA / "logs"
TUNNEL_DIR = DATA / "tunnel"
TMP_DIR = DATA / "tmp"
CONFIG_FILE = DATA / "panel.json"
SESSIONS_FILE = DATA / "sessions.json"
PID_FILE = DATA / "panel.pid"
SERVER_PID_FILE = DATA / "server.pid"
ADDONS_FILE = DATA / "addons.json"
INIT_PW_FILE = DATA / "initial-password.txt"

for _d in (DATA, SERVER_DIR, BACKUP_DIR, LOG_DIR, TUNNEL_DIR, TMP_DIR):
    _d.mkdir(parents=True, exist_ok=True)

BROWSER_UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SHUTDOWN = threading.Event()

# --------------------------------------------------------------------------
# Logs (memoria + arquivo com rotacao)
# --------------------------------------------------------------------------


class Stream:
    """Guarda as ultimas linhas em memoria e grava em logs/<nome>.log (rotacao 5MB x 5)."""

    def __init__(self, name: str, maxlen: int = 4000):
        self.name = name
        self.ring: collections.deque = collections.deque(maxlen=maxlen)
        self.seq = 0
        self.lock = threading.Lock()
        self.listeners: list = []
        self.logger = logging.getLogger("stream." + name)
        self.logger.setLevel(logging.INFO)
        self.logger.propagate = False
        if not self.logger.handlers:
            h = logging.handlers.RotatingFileHandler(
                LOG_DIR / f"{name}.log", maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8")
            h.setFormatter(logging.Formatter("%(asctime)s %(message)s", "%Y-%m-%d %H:%M:%S"))
            self.logger.addHandler(h)

    def add(self, text: str) -> None:
        text = ANSI.sub("", str(text).rstrip("\r\n"))
        with self.lock:
            self.seq += 1
            self.ring.append((self.seq, time.time(), text))
        try:
            self.logger.info(text)
        except Exception:
            pass
        for fn in list(self.listeners):
            try:
                fn(text)
            except Exception:
                pass

    def since(self, n: int):
        with self.lock:
            return [{"i": i, "t": t, "m": m} for (i, t, m) in self.ring if i > n], self.seq


PANEL = Stream("panel")


def plog(msg: str) -> None:
    PANEL.add(msg)
    try:
        print(time.strftime("%H:%M:%S"), msg, flush=True)
    except Exception:
        pass


# --------------------------------------------------------------------------
# Configuracao
# --------------------------------------------------------------------------

DEFAULTS = {
    "panel_host": "127.0.0.1",      # use 0.0.0.0 para acessar de outros aparelhos na mesma rede
    "panel_port": 8080,
    "password_hash": "",
    "autostart": True,              # liga o servidor quando o painel abrir
    "auto_restart": True,           # watchdog: reinicia se cair
    "max_restarts_10min": 5,
    "backup_every_hours": 6,        # 0 = desligado
    "backup_keep": 8,               # quantos backups automaticos manter
    "daily_restart": "",            # "05:00" ou vazio
    "stop_timeout": 45,
    "box64_profile": "balanced",
    "extra_env": {},
    "tunnel_enabled": False,        # playit.gg
    "tunnel_args": [],
    "max_upload_mb": 2048,
    "bds_version": "",
    "command_override": [],         # avancado: comando proprio para iniciar o servidor
}

BOX64_PROFILES = {
    "safe": {"label": "Seguro (mais estavel)",
             "env": {"BOX64_DYNAREC_BIGBLOCK": "0", "BOX64_DYNAREC_STRONGMEM": "1"}},
    "balanced": {"label": "Equilibrado (padrao do box64)", "env": {}},
    "fast": {"label": "Rapido (pode ficar instavel)",
             "env": {"BOX64_DYNAREC_BIGBLOCK": "3", "BOX64_DYNAREC_SAFEFLAGS": "0",
                     "BOX64_DYNAREC_FASTNAN": "1", "BOX64_DYNAREC_FASTROUND": "1",
                     "BOX64_DYNAREC_CALLRET": "1"}},
}
BOX64_BASE = {"BOX64_LOG": "0", "BOX64_NOBANNER": "1", "BOX64_LD_LIBRARY_PATH": "."}


class Config:
    def __init__(self):
        self.lock = threading.Lock()
        self.data = json.loads(json.dumps(DEFAULTS))
        self.load()

    def load(self):
        if CONFIG_FILE.exists():
            try:
                self.data.update(json.loads(CONFIG_FILE.read_text("utf-8")))
            except Exception as e:  # arquivo corrompido nao pode derrubar o painel
                print("panel.json invalido, usando padroes:", e)

    def save(self):
        with self.lock:
            tmp = CONFIG_FILE.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data, indent=2, ensure_ascii=False), "utf-8")
            os.replace(tmp, CONFIG_FILE)
            try:
                os.chmod(CONFIG_FILE, 0o600)
            except OSError:
                pass

    def get(self, key):
        return self.data.get(key, DEFAULTS.get(key))

    def public(self):
        d = {k: v for k, v in self.data.items() if k != "password_hash" and k in DEFAULTS}
        return d

    def update(self, new: dict):
        types = {k: type(v) for k, v in DEFAULTS.items()}
        for k, v in new.items():
            if k not in DEFAULTS or k == "password_hash":
                continue
            t = types[k]
            try:
                if t is bool:
                    v = bool(v)
                elif t is int:
                    v = int(v)
                elif t is str:
                    v = str(v).strip()
                elif t is list:
                    v = [str(x) for x in v] if isinstance(v, list) else []
                elif t is dict:
                    v = {str(a): str(b) for a, b in dict(v).items()}
            except (TypeError, ValueError):
                raise ApiError(400, f"valor invalido para {k}")
            if k == "box64_profile" and v not in BOX64_PROFILES:
                raise ApiError(400, "perfil box64 invalido")
            if k == "daily_restart" and v and not re.fullmatch(r"([01]?\d|2[0-3]):[0-5]\d", v):
                raise ApiError(400, "horario do reinicio diario deve ser HH:MM")
            if k == "panel_port" and not (1024 <= v <= 65535):
                raise ApiError(400, "porta do painel deve ficar entre 1024 e 65535")
            if k in ("backup_every_hours", "backup_keep", "max_restarts_10min", "stop_timeout") and v < 0:
                raise ApiError(400, f"{k} nao pode ser negativo")
            self.data[k] = v
        self.save()


class ApiError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code = code
        self.msg = msg


CFG = Config()

# --------------------------------------------------------------------------
# Senha e sessoes
# --------------------------------------------------------------------------


def hash_password(pw: str) -> str:
    salt = secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 120_000)
    return f"pbkdf2${salt}${h.hex()}"


def verify_password(pw: str) -> bool:
    stored = CFG.get("password_hash") or ""
    try:
        _, salt, hx = stored.split("$")
        h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 120_000)
        return hmac.compare_digest(h.hex(), hx)
    except Exception:
        return False


def set_password(pw: str) -> None:
    if len(pw) < 6:
        raise ApiError(400, "a senha precisa ter pelo menos 6 caracteres")
    CFG.data["password_hash"] = hash_password(pw)
    CFG.save()
    SESSIONS.clear()
    try:
        INIT_PW_FILE.unlink()
    except FileNotFoundError:
        pass


class Sessions:
    TTL = 30 * 86400

    def __init__(self):
        self.lock = threading.Lock()
        self.data: dict = {}
        try:
            self.data = json.loads(SESSIONS_FILE.read_text("utf-8"))
        except Exception:
            self.data = {}

    def _save(self):
        try:
            tmp = SESSIONS_FILE.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data), "utf-8")
            os.replace(tmp, SESSIONS_FILE)
            os.chmod(SESSIONS_FILE, 0o600)
        except OSError:
            pass

    def create(self) -> str:
        sid = secrets.token_hex(32)
        with self.lock:
            now = time.time()
            self.data = {k: v for k, v in self.data.items() if v > now}
            self.data[sid] = now + self.TTL
            self._save()
        return sid

    def valid(self, sid: str) -> bool:
        with self.lock:
            exp = self.data.get(sid)
            return bool(exp and exp > time.time())

    def drop(self, sid: str):
        with self.lock:
            self.data.pop(sid, None)
            self._save()

    def clear(self):
        with self.lock:
            self.data = {}
            self._save()


SESSIONS = Sessions()
LOGIN_FAILS: dict = {}


def init_password() -> None:
    """Garante que existe senha. Usa PANEL_PASSWORD se definido, senao gera uma aleatoria."""
    if CFG.get("password_hash"):
        return
    pw = os.environ.get("PANEL_PASSWORD", "").strip()
    generated = False
    if len(pw) < 6:
        pw = secrets.token_urlsafe(9)
        generated = True
    CFG.data["password_hash"] = hash_password(pw)
    CFG.save()
    if generated:
        INIT_PW_FILE.write_text(pw + "\n", "utf-8")
        try:
            os.chmod(INIT_PW_FILE, 0o600)
        except OSError:
            pass
        plog(f"Senha inicial gerada: {pw}  (tambem em {INIT_PW_FILE})")


# --------------------------------------------------------------------------
# Utilidades de sistema
# --------------------------------------------------------------------------


def is_arm() -> bool:
    return platform.machine().lower() in ("aarch64", "arm64", "armv8l", "armv7l")


def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


_cpu_prev: dict = {}


def proc_stats(pid):
    """CPU% (soma de todos os nucleos, 100 = 1 nucleo cheio) e RSS em MB de um processo."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        rest = data[data.rindex(")") + 2:].split()
        jiff = int(rest[11]) + int(rest[12])
        now = time.time()
        hz = os.sysconf("SC_CLK_TCK")
        prev = _cpu_prev.get(pid)
        cpu = None
        if prev and now - prev[1] >= 0.5:
            cpu = max(0.0, (jiff - prev[0]) / hz / (now - prev[1]) * 100)
            _cpu_prev[pid] = (jiff, now, cpu)
        elif prev:
            cpu = prev[2]
        else:
            _cpu_prev[pid] = (jiff, now, 0.0)
            cpu = 0.0
        rss = None
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    rss = int(line.split()[1]) / 1024
                    break
        return {"cpu": round(cpu, 1) if cpu is not None else None,
                "rss_mb": round(rss, 1) if rss is not None else None}
    except Exception:
        return {"cpu": None, "rss_mb": None}


def system_stats() -> dict:
    out = {"cores": os.cpu_count(), "arch": platform.machine()}
    try:
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                mem[k] = int(v.split()[0]) / 1024
        out["mem_total_mb"] = round(mem.get("MemTotal", 0))
        out["mem_avail_mb"] = round(mem.get("MemAvailable", mem.get("MemFree", 0)))
    except Exception:
        pass
    try:
        out["load"] = [float(x) for x in open("/proc/loadavg").read().split()[:3]]
    except Exception:
        pass
    try:
        du = shutil.disk_usage(DATA)
        out["disk_free_gb"] = round(du.free / 1e9, 1)
        out["disk_total_gb"] = round(du.total / 1e9, 1)
    except Exception:
        pass
    try:
        for base in sorted(Path("/sys/class/power_supply").glob("*")):
            cap = base / "capacity"
            if cap.exists() and (base / "type").exists() and (base / "type").read_text().strip() == "Battery":
                out["battery"] = int(cap.read_text().strip())
                st = base / "status"
                out["charging"] = st.read_text().strip() if st.exists() else None
                break
    except Exception:
        pass
    try:
        temps = []
        for t in Path("/sys/class/thermal").glob("thermal_zone*/temp"):
            try:
                v = int(t.read_text().strip())
                temps.append(v / 1000 if v > 1000 else v)
            except Exception:
                pass
        if temps:
            out["temp_c"] = round(max(temps), 1)
    except Exception:
        pass
    return out


# --------------------------------------------------------------------------
# Propriedades do servidor
# --------------------------------------------------------------------------

PROP_KEY = re.compile(r"^[A-Za-z0-9._-]+$")


def read_props():
    p = SERVER_DIR / "server.properties"
    if not p.exists():
        return None
    txt = p.read_text("utf-8", errors="replace")
    vals = {}
    for line in txt.splitlines():
        s = line.strip()
        if not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        vals[k.strip()] = v.strip()
    return txt, vals


def write_props(changes: dict) -> None:
    for k in changes:
        if not PROP_KEY.match(k):
            raise ApiError(400, f"chave invalida: {k}")
    p = SERVER_DIR / "server.properties"
    lines = p.read_text("utf-8", errors="replace").splitlines() if p.exists() else []
    seen, out = set(), []
    for line in lines:
        s = line.strip()
        if s and not s.startswith("#") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in changes:
                out.append(f"{k}={str(changes[k]).replace(chr(10), ' ').strip()}")
                seen.add(k)
                continue
        out.append(line)
    for k, v in changes.items():
        if k not in seen:
            out.append(f"{k}={str(v).replace(chr(10), ' ').strip()}")
    tmp = p.with_suffix(".tmp")
    tmp.write_text("\n".join(out) + "\n", "utf-8")
    os.replace(tmp, p)


def server_port() -> int:
    r = read_props()
    try:
        return int(r[1].get("server-port", 19132)) if r else 19132
    except ValueError:
        return 19132


# --------------------------------------------------------------------------
# Processo do servidor Bedrock
# --------------------------------------------------------------------------


def server_command():
    ov = CFG.get("command_override")
    if ov:
        return list(ov)
    exe = "./bedrock_server"
    if is_arm():
        b = shutil.which("box64")
        if not b:
            raise RuntimeError("box64 nao encontrado. Rode o setup (ubuntu-setup.sh) para instala-lo.")
        return [b, exe]
    return [exe]


def build_env() -> dict:
    env = os.environ.copy()
    ld = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = "." + (":" + ld if ld else "")
    if is_arm():
        env.update(BOX64_BASE)
        env.update(BOX64_PROFILES.get(CFG.get("box64_profile"), BOX64_PROFILES["balanced"])["env"])
    env.update({str(k): str(v) for k, v in (CFG.get("extra_env") or {}).items()})
    return env


class Bds:
    def __init__(self):
        self.stream = Stream("server")
        self.proc = None
        self.lock = threading.RLock()
        self.state = "stopped"
        self.desired = False
        self.started_at = None
        self.ready = False
        self.version = ""
        self.players: dict = {}
        self.restart_times: list = []
        self.gave_up = False
        self.next_restart_at = 0.0
        self.last_exit = None
        self.maintenance = False
        self.total_restarts = 0
        self.stream.listeners.append(self._parse)

    # ---- leitura do que o servidor imprime
    def _parse(self, line: str):
        if "Server started." in line:
            self.ready = True
            self.state = "running"
        m = re.search(r"Version:\s*([0-9][0-9.]+)", line)
        if m and not self.ready:
            self.version = m.group(1)
        m = re.search(r"Player connected:\s*(.+?),\s*xuid:\s*(\d*)", line)
        if m:
            self.players[m.group(1)] = {"xuid": m.group(2), "since": time.time()}
        m = re.search(r"Player disconnected:\s*(.+?),\s*xuid:", line)
        if m:
            self.players.pop(m.group(1), None)

    def alive(self) -> bool:
        p = self.proc
        return p is not None and p.poll() is None

    def view_state(self) -> str:
        if self.state in ("stopping", "crashed"):
            return self.state
        if self.alive():
            return "running" if self.ready else "starting"
        return "stopped"

    def start(self):
        with self.lock:
            if self.alive():
                return False, "o servidor ja esta ligado"
            if not CFG.get("command_override") and not (SERVER_DIR / "bedrock_server").exists():
                return False, "servidor nao instalado - use Ajustes > Instalar/atualizar"
            try:
                cmd = server_command()
            except RuntimeError as e:
                return False, str(e)
            exe = SERVER_DIR / "bedrock_server"
            if exe.exists():
                try:
                    os.chmod(exe, 0o755)
                except OSError:
                    pass
            self.stream.add("[painel] iniciando: " + " ".join(cmd))
            try:
                self.proc = subprocess.Popen(
                    cmd, cwd=SERVER_DIR, env=build_env(), stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
            except OSError as e:
                self.proc = None
                return False, f"falha ao executar: {e}"
            try:
                SERVER_PID_FILE.write_text(str(self.proc.pid))
            except OSError:
                pass
            self.state = "starting"
            self.ready = False
            self.started_at = time.time()
            self.players.clear()
            self.desired = True
            self.gave_up = False
            threading.Thread(target=self._reader, args=(self.proc,), daemon=True).start()
            return True, "iniciando"

    def _reader(self, proc):
        try:
            for raw in iter(proc.stdout.readline, b""):
                self.stream.add(raw.decode("utf-8", "replace"))
        except Exception as e:
            self.stream.add(f"[painel] erro lendo saida: {e}")
        rc = proc.wait()
        with self.lock:
            if self.proc is proc:
                self.last_exit = {"code": rc, "at": time.time()}
                self.proc = None
                self.players.clear()
                self.ready = False
                self.started_at = None
                self.state = "stopped" if (self.state == "stopping" or not self.desired) else "crashed"
                try:
                    SERVER_PID_FILE.unlink()
                except FileNotFoundError:
                    pass
        self.stream.add(f"[painel] processo terminou (codigo {rc})")

    def send(self, cmd: str) -> bool:
        with self.lock:
            p = self.proc
            if not p or p.poll() is not None:
                return False
            try:
                p.stdin.write((cmd.strip() + "\n").encode("utf-8"))
                p.stdin.flush()
                return True
            except (BrokenPipeError, OSError, ValueError):
                return False

    def stop(self, user: bool = True, timeout=None):
        """Parada graciosa: 'stop' -> SIGTERM -> SIGKILL. user=True cancela o religamento automatico."""
        timeout = timeout or int(CFG.get("stop_timeout") or 45)
        with self.lock:
            if user:
                self.desired = False
            p = self.proc
            if not p or p.poll() is not None:
                if self.state != "crashed" or user:
                    self.state = "stopped"
                return True
            self.state = "stopping"
        self.send("stop")
        try:
            p.wait(timeout)
        except subprocess.TimeoutExpired:
            self.stream.add("[painel] nao parou sozinho, enviando SIGTERM")
            self._signal(p, signal.SIGTERM)
            try:
                p.wait(10)
            except subprocess.TimeoutExpired:
                self.stream.add("[painel] enviando SIGKILL")
                self._signal(p, signal.SIGKILL)
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    pass
        for _ in range(50):  # espera o _reader limpar o estado
            if self.proc is None:
                break
            time.sleep(0.1)
        return True

    def kill(self):
        with self.lock:
            self.desired = False
            p = self.proc
            if p and p.poll() is None:
                self.state = "stopping"
                self._signal(p, signal.SIGKILL)

    @staticmethod
    def _signal(p, sig):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                p.send_signal(sig)
            except Exception:
                pass

    def restart(self):
        self.maintenance = True
        try:
            self.stop(user=False)
            time.sleep(1)
            ok, msg = self.start()
            if not ok:
                plog(f"[painel] reinicio falhou: {msg}")
            return ok, msg
        finally:
            self.maintenance = False

    def command_wait(self, cmd: str, marker: str, timeout: float, linger: float = 0.0):
        got: list = []
        ev = threading.Event()

        def fn(line):
            got.append(line)
            if marker in line:
                ev.set()

        self.stream.listeners.append(fn)
        try:
            if not self.send(cmd):
                return False, got
            ok = ev.wait(timeout)
            if ok and linger:
                time.sleep(linger)
            return ok, list(got)
        finally:
            try:
                self.stream.listeners.remove(fn)
            except ValueError:
                pass


BDS = Bds()


def cleanup_orphan() -> None:
    """Se o painel foi morto a forca, o BDS pode ter ficado vivo. Mata o orfao."""
    try:
        pid = int(SERVER_PID_FILE.read_text().strip())
    except Exception:
        return
    try:
        cmd = Path(f"/proc/{pid}/cmdline").read_bytes().decode("utf-8", "replace")
    except Exception:
        SERVER_PID_FILE.unlink(missing_ok=True)
        return
    if "bedrock_server" in cmd or "box64" in cmd or CFG.get("command_override"):
        plog(f"[painel] matando servidor orfao (pid {pid})")
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(pid, sig)
            except Exception:
                try:
                    os.kill(pid, sig)
                except Exception:
                    pass
            time.sleep(2)
    SERVER_PID_FILE.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# Tunel (playit.gg) - opcional, para jogar de fora da rede local (CGNAT)
# --------------------------------------------------------------------------


class Tunnel:
    def __init__(self):
        self.stream = Stream("tunnel", 800)
        self.proc = None
        self.lock = threading.RLock()
        self.desired = False
        self.claim_url = ""
        self.address = ""
        self.next_restart_at = 0.0
        self.stream.listeners.append(self._parse)

    def _parse(self, line):
        m = re.search(r"https://playit\.gg/claim/\S+", line)
        if m:
            self.claim_url = m.group(0)
        m = re.search(r"([\w.-]+\.(?:joinmc\.link|playit\.gg|gl\.at\.ply\.gg|ply\.gg)(?::\d+)?)", line)
        if m and "claim" not in line:
            self.address = m.group(1)

    @property
    def binary(self) -> Path:
        return TUNNEL_DIR / "playit"

    def installed(self) -> bool:
        return self.binary.exists()

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self):
        with self.lock:
            if self.alive():
                return False, "tunel ja esta ligado"
            if not self.installed():
                return False, "agente playit nao instalado"
            env = os.environ.copy()
            env["HOME"] = str(TUNNEL_DIR)
            cmd = [str(self.binary)] + list(CFG.get("tunnel_args") or [])
            try:
                self.proc = subprocess.Popen(cmd, cwd=TUNNEL_DIR, env=env, stdin=subprocess.DEVNULL,
                                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                             start_new_session=True)
            except OSError as e:
                return False, str(e)
            self.desired = True
            threading.Thread(target=self._reader, args=(self.proc,), daemon=True).start()
            return True, "iniciado"

    def _reader(self, proc):
        for raw in iter(proc.stdout.readline, b""):
            self.stream.add(raw.decode("utf-8", "replace"))
        rc = proc.wait()
        self.stream.add(f"[painel] tunel terminou (codigo {rc})")

    def stop(self):
        with self.lock:
            self.desired = False
            p = self.proc
        if p and p.poll() is None:
            Bds._signal(p, signal.SIGTERM)
            try:
                p.wait(8)
            except subprocess.TimeoutExpired:
                Bds._signal(p, signal.SIGKILL)
        self.proc = None


TUNNEL = Tunnel()


def install_tunnel(progress=lambda p, m: None) -> str:
    name = "playit-linux-aarch64" if is_arm() else "playit-linux-amd64"
    url = f"https://github.com/playit-cloud/playit-agent/releases/latest/download/{name}"
    progress(5, "baixando agente playit.gg...")
    tmp = TMP_DIR / "playit.part"
    download(url, tmp, lambda p: progress(5 + int(p * 0.9), "baixando agente playit.gg..."))
    shutil.move(str(tmp), TUNNEL.binary)
    os.chmod(TUNNEL.binary, 0o755)
    return "agente playit.gg instalado"


# --------------------------------------------------------------------------
# Download / instalacao do BDS
# --------------------------------------------------------------------------


def download(url: str, dest: Path, progress=lambda p: None) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        while True:
            chunk = r.read(1 << 18)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                progress(done * 100 // total)


def latest_bds_url() -> str:
    errs = []
    try:
        req = urllib.request.Request(
            "https://net-secondary.web.minecraft-services.net/api/v1.0/download/links",
            headers={"User-Agent": BROWSER_UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.load(r)
        for link in data.get("result", {}).get("links", []):
            if link.get("downloadType") == "serverBedrockLinux":
                return link["downloadUrl"]
        errs.append("API sem link Linux")
    except Exception as e:
        errs.append(f"API: {e}")
    try:
        req = urllib.request.Request("https://www.minecraft.net/en-us/download/server/bedrock",
                                     headers={"User-Agent": BROWSER_UA})
        with urllib.request.urlopen(req, timeout=20) as r:
            html = r.read().decode("utf-8", "replace")
        m = re.search(r"https://[^\"' ]+/bin-linux/bedrock-server-[\d.]+\.zip", html)
        if m:
            return m.group(0)
        errs.append("pagina sem link")
    except Exception as e:
        errs.append(f"pagina: {e}")
    raise RuntimeError("nao consegui descobrir a ultima versao (" + "; ".join(errs) +
                       "). Informe a versao manualmente, ex.: 1.21.50.07")


PROTECT = ("server.properties", "allowlist.json", "permissions.json")


def install_bds(progress=lambda p, m: None, url=None, version=None) -> str:
    if version:
        if not re.fullmatch(r"[\d.]+", version):
            raise RuntimeError("versao invalida")
        url = f"https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-{version}.zip"
    progress(2, "procurando versao...")
    url = url or latest_bds_url()
    m = re.search(r"bedrock-server-([\d.]+?)\.zip", url)
    new_version = m.group(1) if m else ""
    work = Path(tempfile.mkdtemp(prefix="bds-", dir=TMP_DIR))
    try:
        zpath = work / "bds.zip"
        progress(5, f"baixando {new_version or 'servidor'}...")
        if url.startswith("file://"):
            shutil.copy(urllib.parse.urlsplit(url).path, zpath)
        else:
            download(url, zpath, lambda p: progress(5 + int(p * 0.55), f"baixando {new_version}... {p}%"))
        if not zipfile.is_zipfile(zpath):
            raise RuntimeError("o arquivo baixado nao e um zip valido")
        progress(62, "extraindo...")
        ext = work / "x"
        with zipfile.ZipFile(zpath) as zf:
            zf.extractall(ext)
        if not (ext / "bedrock_server").exists() and not any(ext.glob("*/bedrock_server")):
            raise RuntimeError("zip sem bedrock_server (e a versao Linux?)")
        if not (ext / "bedrock_server").exists():
            ext = next(ext.glob("*/bedrock_server")).parent

        had_world = (SERVER_DIR / "worlds").exists()
        was = BDS.alive() or BDS.desired
        BDS.maintenance = True
        try:
            if BDS.alive():
                progress(66, "parando servidor...")
                BDS.stop(user=False)
            if had_world:
                progress(70, "backup antes de atualizar...")
                make_backup("preupdate", progress=None)
            progress(80, "copiando arquivos...")
            for src in ext.rglob("*"):
                if src.is_dir():
                    continue
                rel = src.relative_to(ext)
                dest = SERVER_DIR / rel
                if rel.parts[0] == "worlds" and dest.exists():
                    continue
                if str(rel) in PROTECT and dest.exists():
                    continue
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dest)
            os.chmod(SERVER_DIR / "bedrock_server", 0o755)
            if new_version:
                CFG.data["bds_version"] = new_version
                CFG.save()
                BDS.version = new_version
            progress(97, "finalizando...")
        finally:
            BDS.maintenance = False
            if was:
                ok, msg = BDS.start()
                if not ok:
                    plog(f"[instalacao] nao consegui religar: {msg}")
        return f"servidor {new_version or ''} instalado"
    finally:
        shutil.rmtree(work, ignore_errors=True)


# --------------------------------------------------------------------------
# Tarefas longas (backup, restauracao, instalacao)
# --------------------------------------------------------------------------


class Jobs:
    def __init__(self):
        self.lock = threading.Lock()
        self.state = {"name": "", "running": False, "pct": 0, "msg": "", "error": None, "ok": None, "at": 0}

    def progress(self, pct, msg):
        with self.lock:
            if pct is not None:
                self.state["pct"] = pct
            if msg:
                self.state["msg"] = msg

    def start(self, name, fn):
        with self.lock:
            if self.state["running"]:
                raise ApiError(409, "ja existe uma tarefa em andamento: " + self.state["name"])
            self.state = {"name": name, "running": True, "pct": 0, "msg": "iniciando...",
                          "error": None, "ok": None, "at": time.time()}

        def run():
            try:
                res = fn(self.progress)
                with self.lock:
                    self.state.update(running=False, ok=True, pct=100, msg=res if isinstance(res, str) else "concluido")
            except Exception as e:
                plog(f"[tarefa {name}] erro: {e}")
                with self.lock:
                    self.state.update(running=False, ok=False, error=str(e), msg=str(e))

        threading.Thread(target=run, daemon=True).start()

    def snapshot(self):
        with self.lock:
            return dict(self.state)


JOBS = Jobs()

# --------------------------------------------------------------------------
# Backups (a quente via save hold / save query / save resume)
# --------------------------------------------------------------------------

BACKUP_LOCK = threading.Lock()
BACKUP_NAME = re.compile(r"^backup-[0-9]{8}-[0-9]{6}-[a-z]+\.zip$")


def load_addons() -> list:
    try:
        return json.loads(ADDONS_FILE.read_text("utf-8"))
    except Exception:
        return []


def save_addons(items: list) -> None:
    ADDONS_FILE.write_text(json.dumps(items, indent=2, ensure_ascii=False), "utf-8")


def parse_save_query(lines: list) -> dict:
    """Le a resposta do 'save query': lista 'arquivo:tamanho, arquivo:tamanho'."""
    lengths = {}
    idx = None
    for i, ln in enumerate(lines):
        if "Data saved" in ln:
            idx = i
            break
    if idx is None:
        return lengths
    for ln in lines[idx + 1:]:
        ln = re.sub(r"^\[[^\]]*\]\s*", "", ln.strip())
        for part in ln.split(", "):
            if ":" not in part:
                continue
            path, _, n = part.rpartition(":")
            n = n.strip()
            if n.isdigit() and path:
                lengths[path.strip()] = int(n)
    return lengths


def _zip_add(zf: zipfile.ZipFile, path: Path, arc: str, limit) -> None:
    try:
        if limit is None:
            zf.write(path, arc)
            return
        zi = zipfile.ZipInfo.from_file(path, arc)
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(path, "rb") as f, zf.open(zi, "w") as out:
            remaining = limit
            while remaining > 0:
                chunk = f.read(min(1 << 20, remaining))
                if not chunk:
                    break
                out.write(chunk)
                remaining -= len(chunk)
    except FileNotFoundError:
        pass


def make_backup(reason: str = "manual", progress=None) -> str:
    def prog(p, m):
        if progress:
            progress(p, m)

    if not (SERVER_DIR / "worlds").exists():
        raise RuntimeError("ainda nao existe mundo para salvar (ligue o servidor uma vez)")
    if not BACKUP_LOCK.acquire(blocking=False):
        raise RuntimeError("ja existe um backup em andamento")
    held = False
    tmp = None
    try:
        ts = time.strftime("%Y%m%d-%H%M%S")
        name = f"backup-{ts}-{reason}.zip"
        tmp = BACKUP_DIR / (name + ".part")
        lengths: dict = {}
        if BDS.alive() and BDS.ready:
            prog(10, "congelando gravacao (save hold)...")
            BDS.send("save hold")
            held = True
            time.sleep(0.8)
            for attempt in range(40):
                ok, got = BDS.command_wait("save query", "Data saved", 3, linger=1.0)
                if ok:
                    lengths = parse_save_query(got)
                    break
                time.sleep(1)
            else:
                raise RuntimeError("o servidor nao confirmou o 'save query'")
        prog(30, "compactando...")
        includes = ["worlds", "server.properties", "allowlist.json", "permissions.json", "config"]
        for a in load_addons():
            includes.append(a.get("folder", ""))
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for inc in includes:
                if not inc:
                    continue
                base = SERVER_DIR / inc
                if base.is_file():
                    _zip_add(zf, base, inc, None)
                elif base.is_dir():
                    for f in base.rglob("*"):
                        if f.is_file():
                            arc = f.relative_to(SERVER_DIR).as_posix()
                            limit = None
                            if lengths:
                                limit = lengths.get(arc)
                                if limit is None and arc.startswith("worlds/"):
                                    limit = lengths.get(arc[len("worlds/"):])
                            _zip_add(zf, f, arc, limit)
        final = BACKUP_DIR / name
        os.replace(tmp, final)
        tmp = None
        prog(90, "limpando backups antigos...")
        prune_backups()
        plog(f"[backup] {name} ({final.stat().st_size // 1024} KB)")
        return name
    finally:
        if held:
            BDS.send("save resume")
        if tmp is not None and tmp.exists():
            tmp.unlink(missing_ok=True)
        BACKUP_LOCK.release()


def prune_backups() -> None:
    keep = int(CFG.get("backup_keep") or 0)
    if keep <= 0:
        return
    autos = sorted(BACKUP_DIR.glob("backup-*-auto.zip"), key=lambda p: p.name, reverse=True)
    for old in autos[keep:]:
        old.unlink(missing_ok=True)


def list_backups() -> list:
    out = []
    for p in sorted(BACKUP_DIR.glob("backup-*.zip"), key=lambda p: p.name, reverse=True):
        st = p.stat()
        out.append({"name": p.name, "size": st.st_size, "mtime": st.st_mtime,
                    "kind": p.stem.rsplit("-", 1)[-1]})
    return out


def restore_backup(name: str, progress=lambda p, m: None) -> str:
    if not BACKUP_NAME.match(name):
        raise RuntimeError("nome de backup invalido")
    src = BACKUP_DIR / name
    if not src.exists() or not zipfile.is_zipfile(src):
        raise RuntimeError("backup nao encontrado ou corrompido")
    was = BDS.alive() or BDS.desired
    BDS.maintenance = True
    try:
        if BDS.alive():
            progress(10, "parando servidor...")
            BDS.stop(user=False)
        progress(30, "guardando mundo atual em worlds.before-restore...")
        cur = SERVER_DIR / "worlds"
        prev = SERVER_DIR / "worlds.before-restore"
        if cur.exists():
            shutil.rmtree(prev, ignore_errors=True)
            cur.rename(prev)
        progress(55, "extraindo backup...")
        with zipfile.ZipFile(src) as zf:
            zf.extractall(SERVER_DIR)
        progress(95, "pronto")
    finally:
        BDS.maintenance = False
        if was:
            BDS.start()
    return "backup restaurado (o mundo anterior ficou em worlds.before-restore)"


# --------------------------------------------------------------------------
# Addons (.mcaddon / .mcpack)
# --------------------------------------------------------------------------


def _read_manifest(path: Path):
    try:
        return json.loads(path.read_text("utf-8-sig"))
    except Exception:
        return None


def _safe_name(s: str) -> str:
    s = re.sub(r"§.", "", s)
    s = re.sub(r"[^A-Za-z0-9._ -]+", "", s).strip().replace(" ", "_")
    return s[:40] or "pack"


def install_addon(zpath: Path) -> list:
    if not zipfile.is_zipfile(zpath):
        raise ApiError(400, "o arquivo nao e um .mcaddon/.mcpack/.zip valido")
    work = Path(tempfile.mkdtemp(prefix="addon-", dir=TMP_DIR))
    try:
        def unpack(z: Path, dest: Path, depth: int):
            dest.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(z) as zf:
                zf.extractall(dest)
            if depth < 3:
                for inner in list(dest.rglob("*")):
                    if inner.is_file() and inner.suffix.lower() in (".mcpack", ".mcaddon", ".zip") \
                            and zipfile.is_zipfile(inner):
                        unpack(inner, inner.with_suffix(""), depth + 1)

        unpack(zpath, work / "x", 0)
        manifests = [m for m in (work / "x").rglob("manifest.json")]
        if not manifests:
            raise ApiError(400, "nenhum manifest.json encontrado no addon")
        results = []
        registry = load_addons()
        for mf in manifests:
            data = _read_manifest(mf)
            if not data or "header" not in data:
                continue
            uuid = str(data["header"].get("uuid", "")).lower()
            ver = data["header"].get("version", [1, 0, 0])
            if not uuid or not isinstance(ver, list):
                continue
            types = [str(m.get("type", "")).lower() for m in data.get("modules", [])]
            if any(t in ("data", "script", "javascript") for t in types):
                kind, folder_root = "behavior", "behavior_packs"
            elif "resources" in types:
                kind, folder_root = "resource", "resource_packs"
            else:
                results.append({"name": data["header"].get("name", "?"), "skipped": "tipo de modulo nao suportado: " + ",".join(types)})
                continue
            pretty = data["header"].get("name", "")
            if not pretty or pretty.startswith("pack."):
                pretty = mf.parent.name
            folder = f"{folder_root}/{_safe_name(pretty)}_{uuid[:8]}"
            registry = [a for a in registry if a.get("uuid") != uuid]
            dest = SERVER_DIR / folder
            shutil.rmtree(dest, ignore_errors=True)
            shutil.copytree(mf.parent, dest)
            registry.append({"uuid": uuid, "version": ver, "kind": kind, "folder": folder,
                             "name": pretty, "at": time.time(),
                             "script": any(t in ("script", "javascript") for t in types)})
            results.append({"name": pretty, "kind": kind, "uuid": uuid, "script": registry[-1]["script"]})
        if not results:
            raise ApiError(400, "manifest.json invalido")
        save_addons(registry)
        enabled = enable_packs([r for r in results if "uuid" in r], registry)
        for r in results:
            if "uuid" in r:
                r["enabled"] = enabled
        return results
    finally:
        shutil.rmtree(work, ignore_errors=True)


def current_world_dir():
    r = read_props()
    level = (r[1].get("level-name") if r else None) or "Bedrock level"
    d = SERVER_DIR / "worlds" / level
    return d if d.is_dir() else None


def _edit_world_packs(fname: str, add=None, remove_uuid=None) -> bool:
    w = current_world_dir()
    if not w:
        return False
    f = w / fname
    try:
        items = json.loads(f.read_text("utf-8-sig")) if f.exists() else []
    except Exception:
        items = []
    if remove_uuid:
        items = [i for i in items if str(i.get("pack_id", "")).lower() != remove_uuid]
    if add:
        items = [i for i in items if str(i.get("pack_id", "")).lower() != add["uuid"]]
        items.append({"pack_id": add["uuid"], "version": add["version"]})
    f.write_text(json.dumps(items, indent=2), "utf-8")
    return True


def enable_packs(results: list, registry: list) -> bool:
    ok = True
    for r in results:
        rec = next((a for a in registry if a["uuid"] == r["uuid"]), None)
        if not rec:
            continue
        fname = "world_behavior_packs.json" if rec["kind"] == "behavior" else "world_resource_packs.json"
        ok = _edit_world_packs(fname, add=rec) and ok
    return ok


def remove_addon(uuid: str) -> None:
    uuid = uuid.lower()
    reg = load_addons()
    rec = next((a for a in reg if a["uuid"] == uuid), None)
    if not rec:
        raise ApiError(404, "addon nao encontrado")
    shutil.rmtree(SERVER_DIR / rec["folder"], ignore_errors=True)
    _edit_world_packs("world_behavior_packs.json" if rec["kind"] == "behavior" else "world_resource_packs.json",
                      remove_uuid=uuid)
    save_addons([a for a in reg if a["uuid"] != uuid])


# --------------------------------------------------------------------------
# Supervisor 24/7 (watchdog, backup agendado, reinicio diario)
# --------------------------------------------------------------------------

SCHED = {"next_backup": 0.0, "last_daily": ""}


def daily_restart_job():
    BDS.maintenance = True
    try:
        for secs, txt in ((30, "30 segundos"), (10, "10 segundos")):
            BDS.send(f"say Reinicio programado em {txt}")
            time.sleep(20 if secs == 30 else 10)
    finally:
        BDS.maintenance = False
    plog("[agenda] reinicio diario")
    BDS.restart()


def tick():
    now = time.time()
    # --- servidor caiu?
    if BDS.desired and not BDS.alive() and not BDS.maintenance and not BDS.gave_up:
        if CFG.get("auto_restart"):
            if BDS.next_restart_at == 0:
                recent = [t for t in BDS.restart_times if now - t < 600]
                if len(recent) >= int(CFG.get("max_restarts_10min") or 5):
                    BDS.gave_up = True
                    BDS.desired = False
                    plog("[watchdog] muitas quedas seguidas - desisti de religar. Veja o console.")
                    return
                BDS.next_restart_at = now + min(60, 5 * 2 ** len(recent))
                plog(f"[watchdog] servidor caiu, religando em {int(BDS.next_restart_at - now)}s")
            elif now >= BDS.next_restart_at:
                BDS.restart_times.append(now)
                BDS.total_restarts += 1
                BDS.next_restart_at = 0
                ok, msg = BDS.start()
                if not ok:
                    plog(f"[watchdog] falha ao religar: {msg}")
                    BDS.gave_up = True
                    BDS.desired = False
        else:
            BDS.desired = False
    elif BDS.alive():
        BDS.next_restart_at = 0
    # --- tunel
    if TUNNEL.desired and not TUNNEL.alive() and TUNNEL.installed():
        if TUNNEL.next_restart_at == 0:
            TUNNEL.next_restart_at = now + 10
        elif now >= TUNNEL.next_restart_at:
            TUNNEL.next_restart_at = 0
            TUNNEL.start()
    # --- backup agendado
    hours = float(CFG.get("backup_every_hours") or 0)
    if hours > 0:
        if SCHED["next_backup"] == 0:
            SCHED["next_backup"] = now + hours * 3600
        elif now >= SCHED["next_backup"]:
            SCHED["next_backup"] = now + hours * 3600
            if (SERVER_DIR / "worlds").exists() and not JOBS.snapshot()["running"] and not BDS.maintenance:
                try:
                    JOBS.start("backup automatico", lambda p: make_backup("auto", p))
                except ApiError:
                    pass
    else:
        SCHED["next_backup"] = 0
    # --- reinicio diario
    hhmm = CFG.get("daily_restart")
    if hhmm and BDS.alive() and BDS.ready and not BDS.maintenance:
        cur = time.strftime("%H:%M")
        want = ":".join(f"{int(x):02d}" for x in hhmm.split(":"))
        today = time.strftime("%Y-%m-%d")
        if cur == want and SCHED["last_daily"] != today:
            SCHED["last_daily"] = today
            threading.Thread(target=daily_restart_job, daemon=True).start()


def supervisor():
    while not SHUTDOWN.is_set():
        try:
            tick()
        except Exception as e:
            plog(f"[supervisor] erro: {e!r}")
        SHUTDOWN.wait(2)


# --------------------------------------------------------------------------
# Arquivos
# --------------------------------------------------------------------------


def safe_path(rel: str, base: Path = SERVER_DIR) -> Path:
    rel = (rel or "").replace("\\", "/").lstrip("/")
    root = base.resolve()
    p = (root / rel).resolve()
    if p != root and root not in p.parents:
        raise ApiError(400, "caminho fora da pasta do servidor")
    return p


def build_status() -> dict:
    st = BDS.view_state()
    stats = proc_stats(BDS.proc.pid) if BDS.alive() else {"cpu": None, "rss_mb": None}
    sysinfo = system_stats()
    props = read_props()
    ip = local_ip()
    port = server_port()
    now = time.time()
    return {
        "time": now,
        "server": {
            "state": st,
            "installed": (SERVER_DIR / "bedrock_server").exists() or bool(CFG.get("command_override")),
            "pid": BDS.proc.pid if BDS.alive() else None,
            "uptime": int(now - BDS.started_at) if BDS.started_at and BDS.alive() else None,
            "version": BDS.version or CFG.get("bds_version"),
            "players": [{"name": n, **v} for n, v in BDS.players.items()],
            "desired": BDS.desired,
            "gave_up": BDS.gave_up,
            "restart_in": max(0, int(BDS.next_restart_at - now)) if BDS.next_restart_at else None,
            "restarts": BDS.total_restarts,
            "last_exit": BDS.last_exit,
            "cpu": stats["cpu"], "rss_mb": stats["rss_mb"],
            "has_props": props is not None,
            "max_players": (props[1].get("max-players") if props else None),
            "level": (props[1].get("level-name") if props else None),
            "port": port, "ip": ip,
        },
        "tunnel": {"installed": TUNNEL.installed(), "alive": TUNNEL.alive(), "desired": TUNNEL.desired,
                   "claim_url": TUNNEL.claim_url, "address": TUNNEL.address},
        "system": sysinfo,
        "job": JOBS.snapshot(),
        "settings": CFG.public(),
        "profiles": {k: v["label"] for k, v in BOX64_PROFILES.items()},
        "next_backup": SCHED["next_backup"] or None,
    }


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

ROUTES: dict = {}


def route(method: str, path: str, auth: bool = True):
    def deco(fn):
        ROUTES[(method, path)] = (fn, auth)
        return fn
    return deco


class Raw:
    def __init__(self, data: bytes, ctype="text/plain; charset=utf-8", headers=None):
        self.data, self.ctype, self.headers = data, ctype, headers or []


class FileOut:
    def __init__(self, path: Path, name=None, delete_after=False):
        self.path, self.name, self.delete_after = path, name or path.name, delete_after


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "BedrockHost/1.0"

    def log_message(self, *a):
        pass

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")

    def do_PUT(self):
        self.dispatch("PUT")

    def do_DELETE(self):
        self.dispatch("DELETE")

    # -- helpers
    def reply(self, code, body=b"", ctype="application/json", headers=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for k, v in headers or []:
            self.send_header(k, v)
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def json(self, obj, code=200):
        self.reply(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def read_json(self, limit=2_000_000):
        n = int(self.headers.get("Content-Length") or 0)
        if n > limit:
            raise ApiError(413, "corpo grande demais")
        raw = self.rfile.read(n) if n else b"{}"
        try:
            return json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            raise ApiError(400, "JSON invalido")

    def save_body(self, dest: Path, limit_mb: int):
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            raise ApiError(400, "corpo vazio")
        if n > limit_mb * 1024 * 1024:
            raise ApiError(413, f"arquivo maior que o limite de {limit_mb} MB")
        left = n
        with open(dest, "wb") as f:
            while left > 0:
                chunk = self.rfile.read(min(1 << 18, left))
                if not chunk:
                    raise ApiError(400, "upload interrompido")
                f.write(chunk)
                left -= len(chunk)

    def sid(self):
        c = http.cookies.SimpleCookie()
        try:
            c.load(self.headers.get("Cookie", ""))
        except Exception:
            return ""
        return c["bh_sid"].value if "bh_sid" in c else ""

    def authed(self):
        h = self.headers.get("Authorization", "")
        if h.startswith("Bearer "):
            return verify_password(h[7:].strip())
        return SESSIONS.valid(self.sid())

    def client_ip(self):
        return self.client_address[0]

    def send_file(self, fo: FileOut):
        try:
            size = fo.path.stat().st_size
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition",
                             "attachment; filename*=UTF-8''" + urllib.parse.quote(fo.name))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            with open(fo.path, "rb") as f:
                while True:
                    chunk = f.read(1 << 18)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        finally:
            if fo.delete_after:
                fo.path.unlink(missing_ok=True)

    def dispatch(self, method):
        try:
            u = urllib.parse.urlsplit(self.path)
            self.q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}
            if method == "GET" and u.path in ("/", "/index.html"):
                html = (APP_DIR / "ui.html").read_bytes()
                return self.reply(200, html, "text/html; charset=utf-8")
            if u.path == "/favicon.ico":
                return self.reply(204)
            ent = ROUTES.get((method, u.path))
            if not ent:
                raise ApiError(404, "rota nao encontrada")
            fn, need_auth = ent
            if need_auth and not self.authed():
                raise ApiError(401, "nao autenticado")
            res = fn(self)
            if isinstance(res, FileOut):
                return self.send_file(res)
            if isinstance(res, Raw):
                return self.reply(200, res.data, res.ctype, res.headers)
            if isinstance(res, tuple):
                return self.json(res[1], res[0])
            return self.json(res if res is not None else {"ok": True})
        except ApiError as e:
            self.json({"error": e.msg}, e.code)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:  # nunca derruba o painel por erro de uma requisicao
            plog(f"[http] erro em {self.path}: {e!r}")
            try:
                self.json({"error": f"erro interno: {e}"}, 500)
            except Exception:
                pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


# ---- rotas: publico
@route("GET", "/api/ping", auth=False)
def r_ping(h):
    return {"ok": True, "app": "bedrock-host"}


@route("POST", "/api/login", auth=False)
def r_login(h):
    ip = h.client_ip()
    now = time.time()
    cnt, first = LOGIN_FAILS.get(ip, (0, now))
    if now - first > 300:
        cnt, first = 0, now
    if cnt >= 6:
        raise ApiError(429, "muitas tentativas - aguarde alguns minutos")
    pw = str(h.read_json().get("password", ""))
    if not verify_password(pw):
        LOGIN_FAILS[ip] = (cnt + 1, first)
        time.sleep(0.6)
        raise ApiError(401, "senha incorreta")
    LOGIN_FAILS.pop(ip, None)
    sid = SESSIONS.create()
    cookie = f"bh_sid={sid}; Path=/; HttpOnly; SameSite=Strict; Max-Age={Sessions.TTL}"
    return Raw(b'{"ok":true}', "application/json", [("Set-Cookie", cookie)])


@route("POST", "/api/logout")
def r_logout(h):
    SESSIONS.drop(h.sid())
    return Raw(b'{"ok":true}', "application/json",
               [("Set-Cookie", "bh_sid=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")])


@route("GET", "/api/status")
def r_status(h):
    return build_status()


# ---- servidor
@route("POST", "/api/server/start")
def r_start(h):
    ok, msg = BDS.start()
    if not ok:
        raise ApiError(400, msg)
    return {"ok": True, "msg": msg}


@route("POST", "/api/server/stop")
def r_stop(h):
    threading.Thread(target=BDS.stop, kwargs={"user": True}, daemon=True).start()
    return {"ok": True}


@route("POST", "/api/server/restart")
def r_restart(h):
    BDS.desired = True
    threading.Thread(target=BDS.restart, daemon=True).start()
    return {"ok": True}


@route("POST", "/api/server/kill")
def r_kill(h):
    BDS.kill()
    return {"ok": True}


@route("POST", "/api/server/command")
def r_command(h):
    cmd = str(h.read_json().get("cmd", "")).strip()
    if not cmd:
        raise ApiError(400, "comando vazio")
    if "\n" in cmd or "\r" in cmd:
        raise ApiError(400, "um comando por vez")
    if not BDS.send(cmd):
        raise ApiError(409, "servidor desligado")
    BDS.stream.add("> " + cmd)
    return {"ok": True}


@route("GET", "/api/logs")
def r_logs(h):
    src = h.q.get("src", "server")
    stream = {"server": BDS.stream, "panel": PANEL, "tunnel": TUNNEL.stream}.get(src)
    if not stream:
        raise ApiError(400, "origem de log invalida")
    since = int(h.q.get("since", "0") or 0)
    lines, last = stream.since(since)
    if since == 0:
        lines = lines[-600:]
    return {"lines": lines, "last": last}


@route("GET", "/api/logfiles")
def r_logfiles(h):
    out = []
    for p in sorted(LOG_DIR.glob("*.log*")):
        out.append({"name": p.name, "size": p.stat().st_size, "mtime": p.stat().st_mtime})
    return {"files": out}


@route("GET", "/api/logfile")
def r_logfile(h):
    name = h.q.get("name", "")
    if not re.fullmatch(r"[a-z]+\.log(\.\d+)?", name):
        raise ApiError(400, "nome invalido")
    p = LOG_DIR / name
    if not p.exists():
        raise ApiError(404, "nao encontrado")
    return FileOut(p, name)


# ---- propriedades
@route("GET", "/api/properties")
def r_props_get(h):
    r = read_props()
    if r is None:
        return {"exists": False, "values": {}, "raw": ""}
    return {"exists": True, "values": r[1], "raw": r[0]}


@route("PUT", "/api/properties")
def r_props_put(h):
    d = h.read_json()
    if "raw" in d:
        (SERVER_DIR / "server.properties").write_text(str(d["raw"]), "utf-8")
    else:
        write_props({str(k): v for k, v in (d.get("values") or {}).items()})
    if d.get("restart"):
        BDS.desired = True
        threading.Thread(target=BDS.restart, daemon=True).start()
    return {"ok": True}


# ---- arquivos
@route("GET", "/api/files")
def r_files(h):
    p = safe_path(h.q.get("path", ""))
    if not p.is_dir():
        raise ApiError(404, "pasta nao encontrada")
    items = []
    for c in sorted(p.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower())):
        try:
            st = c.stat()
        except OSError:
            continue
        items.append({"name": c.name, "dir": c.is_dir(), "size": st.st_size, "mtime": st.st_mtime})
    rel = p.relative_to(SERVER_DIR.resolve()).as_posix()
    return {"path": "" if rel == "." else rel, "items": items}


@route("GET", "/api/file")
def r_file_read(h):
    p = safe_path(h.q.get("path", ""))
    if not p.is_file():
        raise ApiError(404, "arquivo nao encontrado")
    if p.stat().st_size > 2_000_000:
        raise ApiError(413, "arquivo grande demais para editar - baixe-o")
    data = p.read_bytes()
    if b"\0" in data[:4096]:
        raise ApiError(415, "arquivo binario - baixe-o")
    return {"content": data.decode("utf-8", "replace")}


@route("PUT", "/api/file")
def r_file_write(h):
    d = h.read_json(limit=4_000_000)
    p = safe_path(str(d.get("path", "")))
    if p.is_dir():
        raise ApiError(400, "isso e uma pasta")
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(str(d.get("content", "")), "utf-8")
    os.replace(tmp, p)
    return {"ok": True}


@route("POST", "/api/files/mkdir")
def r_mkdir(h):
    p = safe_path(str(h.read_json().get("path", "")))
    p.mkdir(parents=True, exist_ok=True)
    return {"ok": True}


@route("DELETE", "/api/files")
def r_delete(h):
    p = safe_path(h.q.get("path", ""))
    if p == SERVER_DIR.resolve():
        raise ApiError(400, "nao e possivel apagar a raiz")
    if p.is_dir():
        shutil.rmtree(p)
    elif p.exists():
        p.unlink()
    else:
        raise ApiError(404, "nao encontrado")
    return {"ok": True}


@route("GET", "/api/files/download")
def r_download(h):
    p = safe_path(h.q.get("path", ""))
    if p.is_file():
        return FileOut(p)
    if p.is_dir():
        tmp = Path(tempfile.mkstemp(suffix=".zip", dir=TMP_DIR)[1])
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in p.rglob("*"):
                if f.is_file():
                    _zip_add(zf, f, f.relative_to(p).as_posix(), None)
        return FileOut(tmp, (p.name or "servidor") + ".zip", delete_after=True)
    raise ApiError(404, "nao encontrado")


@route("POST", "/api/files/upload")
def r_upload(h):
    name = os.path.basename(h.q.get("name", ""))
    if not name:
        raise ApiError(400, "nome do arquivo ausente")
    folder = safe_path(h.q.get("path", ""))
    if not folder.is_dir():
        raise ApiError(404, "pasta de destino nao existe")
    dest = safe_path((folder / name).relative_to(SERVER_DIR.resolve()).as_posix())
    tmp = dest.with_name(dest.name + ".part")
    try:
        h.save_body(tmp, int(CFG.get("max_upload_mb") or 2048))
        os.replace(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)
    return {"ok": True}


# ---- backups
@route("GET", "/api/backups")
def r_backups(h):
    return {"items": list_backups(), "next": SCHED["next_backup"] or None}


@route("POST", "/api/backups")
def r_backup_create(h):
    JOBS.start("backup", lambda p: make_backup("manual", p))
    return {"ok": True}


@route("POST", "/api/backups/restore")
def r_backup_restore(h):
    name = str(h.read_json().get("name", ""))
    if not BACKUP_NAME.match(name):
        raise ApiError(400, "nome invalido")
    JOBS.start("restaurar " + name, lambda p: restore_backup(name, p))
    return {"ok": True}


@route("DELETE", "/api/backups")
def r_backup_delete(h):
    name = h.q.get("name", "")
    if not BACKUP_NAME.match(name):
        raise ApiError(400, "nome invalido")
    (BACKUP_DIR / name).unlink(missing_ok=True)
    return {"ok": True}


@route("GET", "/api/backups/download")
def r_backup_download(h):
    name = h.q.get("name", "")
    if not BACKUP_NAME.match(name) or not (BACKUP_DIR / name).exists():
        raise ApiError(404, "nao encontrado")
    return FileOut(BACKUP_DIR / name)


# ---- addons
@route("GET", "/api/addons")
def r_addons(h):
    return {"items": load_addons(), "world": bool(current_world_dir())}


@route("POST", "/api/addons/upload")
def r_addon_upload(h):
    name = os.path.basename(h.q.get("name", "addon.mcaddon"))
    tmp = TMP_DIR / ("up-" + secrets.token_hex(4) + "-" + re.sub(r"[^A-Za-z0-9._-]", "_", name))
    try:
        h.save_body(tmp, 512)
        res = install_addon(tmp)
    finally:
        tmp.unlink(missing_ok=True)
    return {"ok": True, "results": res, "world": bool(current_world_dir())}


@route("DELETE", "/api/addons")
def r_addon_delete(h):
    remove_addon(h.q.get("uuid", ""))
    return {"ok": True}


# ---- ajustes / sistema
@route("GET", "/api/settings")
def r_settings_get(h):
    return {"settings": CFG.public(), "profiles": {k: v["label"] for k, v in BOX64_PROFILES.items()}}


@route("PUT", "/api/settings")
def r_settings_put(h):
    CFG.update(h.read_json().get("settings", {}))
    SCHED["next_backup"] = 0
    return {"ok": True}


@route("POST", "/api/password")
def r_password(h):
    d = h.read_json()
    if not verify_password(str(d.get("old", ""))):
        raise ApiError(403, "senha atual incorreta")
    set_password(str(d.get("new", "")))
    sid = SESSIONS.create()
    cookie = f"bh_sid={sid}; Path=/; HttpOnly; SameSite=Strict; Max-Age={Sessions.TTL}"
    return Raw(b'{"ok":true}', "application/json", [("Set-Cookie", cookie)])


@route("POST", "/api/install")
def r_install(h):
    d = h.read_json()
    url = str(d.get("url", "")).strip() or None
    ver = str(d.get("version", "")).strip() or None
    if url and not re.match(r"^https://", url):
        raise ApiError(400, "a URL precisa comecar com https://")
    JOBS.start("instalar servidor", lambda p: install_bds(p, url=url, version=ver))
    return {"ok": True}


@route("POST", "/api/tunnel/install")
def r_tunnel_install(h):
    JOBS.start("instalar tunel", install_tunnel)
    return {"ok": True}


@route("POST", "/api/tunnel/start")
def r_tunnel_start(h):
    ok, msg = TUNNEL.start()
    if not ok:
        raise ApiError(400, msg)
    CFG.update({"tunnel_enabled": True})
    return {"ok": True}


@route("POST", "/api/tunnel/stop")
def r_tunnel_stop(h):
    TUNNEL.stop()
    CFG.update({"tunnel_enabled": False})
    return {"ok": True}


# --------------------------------------------------------------------------
# Inicializacao / desligamento
# --------------------------------------------------------------------------

HTTPD = None


def graceful_shutdown(*_):
    if SHUTDOWN.is_set():
        return
    SHUTDOWN.set()
    plog("[painel] desligando...")
    threading.Thread(target=lambda: HTTPD.shutdown() if HTTPD else None, daemon=True).start()


def main_cli(argv) -> int:
    if "--set-password" in argv:
        i = argv.index("--set-password")
        if i + 1 >= len(argv):
            print("uso: panel.py --set-password SENHA")
            return 2
        try:
            set_password(argv[i + 1])
        except ApiError as e:
            print("erro:", e.msg)
            return 1
        print("senha atualizada.")
        return 0
    if "--print-password" in argv:
        print(INIT_PW_FILE.read_text().strip() if INIT_PW_FILE.exists()
              else "(sem senha inicial salva - defina uma com --set-password)")
        return 0
    if "--install" in argv:
        ver = argv[argv.index("--version") + 1] if "--version" in argv else None
        url = argv[argv.index("--url") + 1] if "--url" in argv else None
        last = [-1]

        def pr(p, m):
            if p != last[0]:
                last[0] = p
                print(f"[{p:3d}%] {m}", flush=True)
        try:
            print(install_bds(pr, url=url, version=ver))
            return 0
        except Exception as e:
            print("erro:", e)
            return 1
    if "--install-tunnel" in argv:
        try:
            print(install_tunnel(lambda p, m: print(f"[{p}%] {m}", flush=True)))
            return 0
        except Exception as e:
            print("erro:", e)
            return 1
    return -1


def main():
    global HTTPD
    rc = main_cli(sys.argv[1:])
    if rc >= 0:
        sys.exit(rc)
    init_password()
    cleanup_orphan()
    PID_FILE.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, graceful_shutdown)
    signal.signal(signal.SIGINT, graceful_shutdown)
    host, port = CFG.get("panel_host"), int(CFG.get("panel_port"))
    HTTPD = Server((host, port), Handler)
    plog(f"[painel] ouvindo em http://{host}:{port}  (dados em {DATA})")
    threading.Thread(target=supervisor, daemon=True).start()
    if CFG.get("autostart") and ((SERVER_DIR / "bedrock_server").exists() or CFG.get("command_override")):
        ok, msg = BDS.start()
        plog(f"[painel] autostart: {msg}")
    if CFG.get("tunnel_enabled") and TUNNEL.installed():
        TUNNEL.start()
    try:
        HTTPD.serve_forever(poll_interval=0.5)
    finally:
        SHUTDOWN.set()
        plog("[painel] parando tunel e servidor...")
        TUNNEL.stop()
        BDS.stop(user=True)
        try:
            PID_FILE.unlink()
        except FileNotFoundError:
            pass
        plog("[painel] encerrado.")


if __name__ == "__main__":
    main()
