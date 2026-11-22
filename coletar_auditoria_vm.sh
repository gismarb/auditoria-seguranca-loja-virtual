#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: coletar_auditoria_vm.sh
# Autor: Gismar Pereira Barbosa
# Data de criação: 21/11/2026
# Revisão: 1.0 (versão inicial)
# Motivo: Automatizar a coleta de evidências na VM da Loja Virtual LTDA
#         e gerar arquivos CSV e HTML para apoiar a análise de auditoria.
# -----------------------------------------------------------------------------

set -euo pipefail
umask 077

if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'É necessário ter Python 3 disponível na VM.' >&2
    exit 1
fi

exec python3 - "$@" <<'PY'
import argparse
import csv
import gzip
import html
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

parser = argparse.ArgumentParser(
    prog="coletar_auditoria_vm.sh",
    description="Coleta local dos seis controles operacionais da Loja Virtual LTDA."
)
parser.add_argument("--wp-path", type=Path, help="Diretório da instalação WordPress")
parser.add_argument("--backup-dir", type=Path, action="append", default=[],
                    help="Diretório adicional de backups (opção repetível)")
parser.add_argument("--saida", type=Path, default=Path.cwd(),
                    help="Diretório existente no qual será criada uma pasta para a coleta")
args = parser.parse_args()
now = datetime.now().astimezone()
rows = []
groups = {
    "CTX": "Identificação da coleta",
    "VM-01": "Backup do banco de dados",
    "VM-02": "Teste do backup do banco de dados",
    "VM-03": "Atualização do gerenciador do banco de dados",
    "VM-04": "Atualização do sistema web LojaVirtual",
    "VM-05": "Controle de acesso/usuário",
    "VM-06": "Atualização do sistema de hospedagem de páginas",
}


def row(control, check, status, value, source):
    rows.append((control, groups[control], check, status, value, source))


def command(*args):
    try:
        result = subprocess.run(
            args, capture_output=True, text=True, errors="replace",
            timeout=12, env=dict(os.environ, LC_ALL="C"),
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def read_text(path, limit=256_000):
    try:
        with path.open(encoding="utf-8", errors="replace") as file:
            return file.read(limit)
    except OSError:
        return None


def stamp(seconds):
    return datetime.fromtimestamp(seconds).astimezone().isoformat(timespec="seconds")


def walk(root, depth):
    root = root.resolve()
    errors = []
    for base, folders, files in os.walk(root, onerror=errors.append):
        current = Path(base)
        if len(current.relative_to(root).parts) >= depth:
            folders[:] = []
        else:
            folders[:] = sorted(name for name in folders if not name.startswith("."))
        yield current, files
    if errors:
        raise errors[0]


os_release = read_text(Path("/etc/os-release")) or ""
match = re.search(r'^PRETTY_NAME=(.+)$', os_release, re.MULTILINE)
row("CTX", "Sistema operacional", "Informativo",
    match.group(1).strip('"') if match else "Não identificado", "/etc/os-release")
row("CTX", "Data e hora local", "Informativo", now.isoformat(timespec="seconds"),
    "Relógio da VM")
row("CTX", "Privilégio da coleta", "Informativo",
    "administrador (root)" if os.geteuid() == 0 else "usuário comum",
    "Usuário que executou a coleta")

# Registro de políticas APT. A comparação se limita ao índice local.
package_output = command("dpkg-query", "-W", "-f=${Package}\t${Version}\t${Status}\n")
installed = {}
for line in (package_output or "").splitlines():
    fields = line.split("\t")
    if len(fields) == 3 and fields[2] == "install ok installed":
        installed[fields[0]] = fields[1]

index_dates = [
    path.stat().st_mtime
    for path in Path("/var/lib/apt/lists").glob("*_Packages*")
    if path.is_file()
]
row("CTX", "Índices locais APT", "Informativo",
    "Índice de pacotes mais recente por data do arquivo: " + stamp(max(index_dates))
    if index_dates else "Índices de pacotes não localizados",
    "/var/lib/apt/lists (data de arquivo, sem consulta de rede)")

package_groups = {
    "VM-03": r"(?:mariadb|mysql)-(?:server|server-core)(?:-[\d.]+)?",
    "VM-06": r"apache2(?:-bin|-data|-utils)?|libapache2-mod-php[\d.]*|php[\d.]*(?:-fpm|-common)?",
}
selected = {control: sorted(p for p in installed if re.fullmatch(pattern, p))
            for control, pattern in package_groups.items()}
package_history = {}
for path in sorted(Path("/var/log").glob("dpkg.log*")):
    if not re.fullmatch(r"dpkg\.log(?:\.\d+(?:\.gz)?)?", path.name):
        continue
    try:
        opener = gzip.open if path.suffix == ".gz" else open
        with opener(path, "rt", encoding="utf-8", errors="replace") as logfile:
            for line in logfile:
                fields = line.split()
                if len(fields) < 6 or fields[2] != "upgrade":
                    continue
                package = fields[3].split(":")[0]
                if package in installed and fields[4] != fields[5]:
                    event = (" ".join(fields[:2]), fields[4], fields[5])
                    if event > package_history.get(package, ("",)):
                        package_history[package] = event
    except (OSError, EOFError):
        continue

for control, packages in selected.items():
    if not packages:
        row(control, "Pacotes de servidor", "Não verificado",
            "Nenhum pacote correspondente identificado no inventário dpkg.",
            "dpkg-query")
    for package in packages:
        policy = command("apt-cache", "policy", package) or ""
        candidate = re.search(r"^\s*Candidate:\s*(\S+)", policy, re.MULTILINE)
        candidate = candidate.group(1) if candidate else "(none)"
        version = installed[package]
        result = "Instalada: " + version
        if candidate != "(none)":
            result += " | Candidata no índice local: " + candidate
            if command("dpkg", "--compare-versions", version, "lt", candidate) is not None:
                result += " | Candidata mais recente no índice local"
            elif candidate != version:
                result += " | Versões diferentes"
        else:
            result += " | Candidata não identificada"
        if package in package_history:
            date, old, new = package_history[package]
            result += f" | Último upgrade localizado: {date}, {old} → {new}"
        else:
            result += " | Upgrade não localizado nos logs legíveis"
        row(control, package, "Coletado", result, "dpkg-query, apt-cache policy e logs dpkg")

for control, services in (
    ("VM-03", ("mariadb.service", "mysql.service")),
    ("VM-06", ("apache2.service",)),
):
    for service in services:
        info = command("systemctl", "show", "-p", "LoadState", "-p", "ActiveState", service)
        row(control, service, "Coletado" if info else "Não verificado",
            " | ".join(info.splitlines()) if info else "Estado indisponível.",
            "systemctl show")

# Leio os metadados de versão e preservo o conteúdo do wp-config.php.
wp_roots = set()
if args.wp_path:
    wp_roots.add(args.wp_path.resolve())
else:
    for directory in (Path("/var/www"), Path("/srv/www")):
        if not directory.is_dir():
            continue
        try:
            for current, _ in walk(directory, 5):
                if (current / "wp-includes/version.php").is_file():
                    wp_roots.add(current)
        except OSError:
            row("VM-04", "Busca do WordPress", "Parcial",
                "Parte do diretório está inacessível.", str(directory))

usable_roots = []
for root in sorted(wp_roots):
    version_file = root / "wp-includes/version.php"
    source = read_text(version_file) or ""
    version = re.search(r"""\$wp_version\s*=\s*['"]([\w.+-]+)['"]""", source)
    if version:
        usable_roots.append(root)
    row("VM-04", "Versão do WordPress", "Coletado" if version else "Não verificado",
        version.group(1) if version else "Versão não identificada.",
        str(version_file))
    plugin_file = root / "wp-content/plugins/woocommerce/woocommerce.php"
    source = read_text(plugin_file, 8192) or ""
    version = re.search(r"^\s*\*?\s*Version:\s*([\w.+-]+)", source, re.MULTILINE)
    if version:
        row("VM-04", "Versão do WooCommerce", "Coletado",
            version.group(1), str(plugin_file))

if not wp_roots:
    row("VM-04", "Instalação do WordPress", "Não verificado",
        "Instalação não localizada. Use --wp-path se estiver fora dos diretórios consultados.",
        "/var/www e /srv/www")
if len(usable_roots) > 1:
    row("VM-04", "Identificação da loja", "Verificação manual",
        "Mais de uma instalação encontrada. Confirme o diretório da loja auditada.", "--wp-path")

row("VM-04", "Situação das atualizações", "Verificação manual",
    "Registrar, no painel do WordPress, a data da última verificação, versões e pendências de núcleo, tema ativo e plugins usados na loja.", "Painel → Atualizações")
row("VM-05", "Perfis e restrição de acesso", "Verificação manual",
    "Conferir os perfis no painel. Em sessão separada, validar o acesso permitido de uma conta de teste existente e registrar a restrição ao painel para um perfil sem permissão administrativa. Omitir dados pessoais.", "Painel → Usuários e observação da sessão de teste")

# Busco apenas nomes e metadados de arquivos, sem ler dumps ou registros da loja.
backup_roots = {Path("/var/backups"), Path("/srv/backups"), Path("/backup"), Path("/backups")}
backup_roots.update(p.resolve() for p in args.backup_dir)
suffix = r"\.(?:sql(?:\.(?:gz|bz2|xz|zst|zip))?|dump(?:\.(?:gz|xz|zst))?|xbstream)(?:\.part\d+)?$"
backup_pattern = re.compile(suffix, re.I)
plugin_pattern = re.compile(r"(?:^|[-_])db(?:\d+)?\.gz$", re.I)
for root in usable_roots:
    backup_roots.update(root / "wp-content" / folder for folder in (
        "updraft", "ai1wm-backups", "backups", "uploads/backup", "uploads/backups"
    ))

counts = {}
for root in sorted(backup_roots):
    count = 0
    latest = 0
    partial = False
    if not root.is_dir():
        if root in {p.resolve() for p in args.backup_dir}:
            row("VM-01", "Diretório indicado", "Não verificado",
                "Diretório não localizado ou inacessível.", str(root))
        continue
    try:
        for base, files in walk(root, 4):
            for name in files:
                if not (backup_pattern.search(name) or plugin_pattern.search(name)
                        or name.endswith(".wpress") or name == "xtrabackup_checkpoints"):
                    continue
                path = base / name
                if path.is_symlink() or not path.is_file():
                    continue
                metadata = path.stat()
                if metadata.st_size:
                    count += 1
                    latest = max(latest, metadata.st_mtime)
    except OSError:
        partial = True
    counts[root] = count
    row("VM-01", "Artefatos de backup", "Parcial" if partial else "Coletado",
        f"{count} arquivo(s) candidato(s) com tamanho maior que zero"
        + (f" | Modificação mais recente: {stamp(latest)}" if latest else "")
        + (" | Parte do diretório não pôde ser lida." if partial else ""),
        str(root))

if not counts:
    row("VM-01", "Diretórios de backup", "Não verificado",
        "Nenhum diretório padrão ou informado pôde ser inspecionado.",
        "Diretórios padrão e opção --backup-dir")

cron_files = [Path("/etc/crontab")]
for directory in ("/etc/cron.d", "/etc/cron.daily", "/etc/cron.weekly",
                  "/etc/cron.monthly", "/var/spool/cron/crontabs"):
    try:
        cron_files.extend(path for path in Path(directory).iterdir()
                          if path.is_file() and not path.is_symlink())
    except OSError:
        continue
matched = 0
for path in cron_files:
    source = read_text(path) or ""
    lines = (line for line in source.splitlines()
             if line.strip() and not line.lstrip().startswith("#"))
    if any(re.search(r"\b(?:mysqldump|mariadb-dump|mariabackup|mariadb-backup)\b", line)
           for line in lines):
        matched += 1
row("VM-01", "Agendamento cron", "Indício" if matched else "Não localizado",
    f"{matched} arquivo(s) legível(is) com referência direta a utilitário de backup. Verificar o banco de destino e o último resultado na rotina ou no plugin.",
    "Arquivos cron locais (comandos omitidos)")
row("VM-02", "Evidência do teste de restauração", "Verificação manual",
    "Procurar registro anterior com data, backup utilizado, validação e resultado. Quando houver teste novo, identificar a data e usar ambiente isolado da loja.",
    "Registro de teste ou verificação isolada")

headers = ("ID", "Controle", "Verificação", "Situação da coleta", "Evidência", "Fonte")
try:
    output = args.saida.resolve() / now.strftime("evidencias-auditoria-%Y%m%d-%H%M%S-%f")
    output.mkdir(mode=0o700)
except OSError as exc:
    parser.exit(1, f"Não foi possível criar a pasta de saída: {exc}\n")

with (output / "evidencias-auditoria.csv").open("w", encoding="utf-8-sig", newline="") as file:
    writer = csv.writer(file, delimiter=";", quoting=csv.QUOTE_ALL)
    writer.writerow(headers)
    for entry in rows:
        writer.writerow([
            "'" + value if value.lstrip().startswith(("=", "+", "-", "@")) else value
            for value in entry
        ])

with (output / "evidencias-auditoria.html").open("w", encoding="utf-8") as file:
    file.write("""<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Evidências da auditoria — Loja Virtual LTDA</title>
<style>
body{font:1rem/1.5 system-ui,sans-serif;margin:0 auto;max-width:1100px;padding:2rem;color:#172b3b;background:#f4f7f9}
h1,h2{line-height:1.2} h2{margin-top:2rem}
table{width:100%;border-collapse:collapse;background:#fff}
th,td{padding:.65rem;text-align:left;vertical-align:top;border-bottom:1px solid #d7e1ea;overflow-wrap:anywhere}
th{background:#1d4661;color:#fff} nav a{margin-right:.8rem;color:#164f73}
@media print{body{padding:0;background:#fff}th{background:#fff;color:#172b3b}tr{break-inside:avoid}}
</style>
<body>
<main>
<h1>Evidências da auditoria da VM</h1>
<p>Loja Virtual LTDA · Coleta de evidências para o checklist de auditoria.</p>
<p>A situação de cada linha indica o resultado da coleta. A conclusão sobre os controles depende da avaliação da evidência.</p>
<nav aria-label="Controles auditados">""")
    for control in groups:
        label = "Identificação" if control == "CTX" else control
        file.write(f'<a href="#{control}">{label}</a>')
    file.write("</nav>\n")
    for control, title in groups.items():
        heading = f"{control} · {title}" if control != "CTX" else title
        file.write(f'<section id="{control}"><h2>{html.escape(heading)}</h2><table><thead><tr>')
        for header in headers[2:]:
            file.write(f'<th scope="col">{html.escape(header)}</th>')
        file.write("</tr></thead><tbody>")
        for entry in rows:
            if entry[0] != control:
                continue
            file.write("<tr>" + "".join(f"<td>{html.escape(v)}</td>" for v in entry[2:]) + "</tr>\n")
        file.write("</tbody></table></section>\n")
    file.write("</main></body></html>\n")

print(f"Arquivos CSV e HTML gravados em: {output}")
PY
