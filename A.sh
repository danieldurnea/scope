#!/usr/bin/env bash
# =============================================================================
# install-quantumcryptotrader.sh
# Instaleaza, compileaza si porneste QuantumCryptoTrader pe VPS Windows
# Compatibil cu: WSL2, Git Bash, Cygwin
# Rulare: bash install-quantumcryptotrader.sh
# =============================================================================

set -euo pipefail

# --- Culori ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
OK()   { echo -e "${GREEN}[OK]${NC}   $*"; }
WARN() { echo -e "${YELLOW}[WARN]${NC} $*"; }
INFO() { echo -e "${CYAN}[..]${NC}   $*"; }
FAIL() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
HEAD() { echo -e "\n${CYAN}>>> $*${NC}"; }

# =============================================================================
# CONFIGURATIE — editeaza dupa nevoie
# =============================================================================

EA_FILE="QuantumCryptoTrader.mq5"          # fisierul EA (in acelasi folder cu scriptul)
EA_NAME="QuantumCryptoTrader"              # fara extensie

# --- Detectare automata cale Windows home (WSL / Git Bash / Cygwin) ---
detect_winuser() {
    if command -v powershell.exe &>/dev/null; then
        powershell.exe -NoProfile -Command "[System.Environment]::GetFolderPath('UserProfile')" \
            2>/dev/null | tr -d '\r'
    elif command -v cmd.exe &>/dev/null; then
        cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n'
    else
        echo ""
    fi
}

WIN_HOME=$(detect_winuser)

# Converteste cale Windows -> cale Unix (WSL / Cygwin / Git Bash)
to_unix_path() {
    local winpath="$1"
    if [[ -n "$(uname -r 2>/dev/null | grep -i microsoft)" ]]; then
        # WSL
        wslpath -u "$winpath" 2>/dev/null || echo "$winpath"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        # Git Bash / Cygwin
        echo "$winpath" | sed 's|\\|/|g; s|C:|/c|; s|D:|/d|'
    else
        echo "$winpath"
    fi
}

WIN_HOME_UNIX=$(to_unix_path "$WIN_HOME")

# --- Cai MT5 candidate (ordine prioritate) ---
MT5_CANDIDATES=(
    "$WIN_HOME_UNIX/AppData/Roaming/MetaQuotes/Terminal"
    "/c/Program Files/MetaTrader 5"
    "/c/Program Files (x86)/MetaTrader 5"
    "$WIN_HOME_UNIX/AppData/Local/Programs/MetaTrader 5"
)

# Override manual (decomenteaza si seteaza daca detectia esueaza):
# MT5_TERMINAL_DIR="/c/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/ABCDEF1234567890"
# MT5_EXE="/c/Program Files/MetaTrader 5/terminal64.exe"
# METAEDITOR_EXE="/c/Program Files/MetaTrader 5/metaeditor64.exe"

# =============================================================================
# BANNER
# =============================================================================
echo
echo "============================================================"
echo "  QuantumCryptoTrader — Installer"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo

# =============================================================================
# 1. VERIFICARE MEDIU
# =============================================================================
HEAD "Verificare mediu de rulare"

SHELL_ENV="unknown"
if [[ -n "$(uname -r 2>/dev/null | grep -i microsoft)" ]]; then
    SHELL_ENV="wsl"
    OK "Mediu detectat: WSL2"
elif [[ "$OSTYPE" == "msys" ]]; then
    SHELL_ENV="gitbash"
    OK "Mediu detectat: Git Bash"
elif [[ "$OSTYPE" == "cygwin" ]]; then
    SHELL_ENV="cygwin"
    OK "Mediu detectat: Cygwin"
else
    WARN "Mediu necunoscut: $OSTYPE — incearca oricum"
fi

INFO "Windows home: $WIN_HOME"

# =============================================================================
# 2. VERIFICARE FISIER EA
# =============================================================================
HEAD "Verificare fisier EA"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EA_SOURCE="$SCRIPT_DIR/$EA_FILE"

if [[ ! -f "$EA_SOURCE" ]]; then
    FAIL "$EA_FILE nu a fost gasit in $SCRIPT_DIR"
fi
OK "EA source: $EA_SOURCE"

# =============================================================================
# 3. DETECTARE METAEDITOR + TERMINAL
# =============================================================================
HEAD "Detectare instalare MetaTrader 5"

find_mt5_exe() {
    local name="$1"
    # Cauta in locatii comune
    for base in \
        "/c/Program Files/MetaTrader 5" \
        "/c/Program Files (x86)/MetaTrader 5" \
        "$WIN_HOME_UNIX/AppData/Local/Programs/MetaTrader 5" \
        "$WIN_HOME_UNIX/Desktop/MetaTrader 5"
    do
        if [[ -f "$base/$name" ]]; then
            echo "$base/$name"
            return 0
        fi
    done
    return 1
}

# MetaEditor
if [[ -z "${METAEDITOR_EXE:-}" ]]; then
    METAEDITOR_EXE=$(find_mt5_exe "metaeditor64.exe" 2>/dev/null || \
                     find_mt5_exe "metaeditor.exe"   2>/dev/null || echo "")
fi

if [[ -z "$METAEDITOR_EXE" ]]; then
    WARN "metaeditor64.exe nu a fost gasit automat."
    INFO "Seteaza manual: export METAEDITOR_EXE='/c/Program Files/MetaTrader 5/metaeditor64.exe'"
    read -rp "  Introdu calea completa catre metaeditor64.exe: " METAEDITOR_EXE
    [[ -f "$METAEDITOR_EXE" ]] || FAIL "Fisier inexistent: $METAEDITOR_EXE"
fi
OK "MetaEditor: $METAEDITOR_EXE"

# terminal64.exe
if [[ -z "${MT5_EXE:-}" ]]; then
    MT5_EXE=$(find_mt5_exe "terminal64.exe" 2>/dev/null || \
              find_mt5_exe "terminal.exe"   2>/dev/null || echo "")
fi

if [[ -z "$MT5_EXE" ]]; then
    WARN "terminal64.exe nu a fost gasit automat."
    read -rp "  Introdu calea completa catre terminal64.exe: " MT5_EXE
    [[ -f "$MT5_EXE" ]] || FAIL "Fisier inexistent: $MT5_EXE"
fi
OK "Terminal: $MT5_EXE"

MT5_INSTALL_DIR="$(dirname "$MT5_EXE")"

# =============================================================================
# 4. DETECTARE DATA FOLDER (unde sunt Experts, logs etc.)
# =============================================================================
HEAD "Detectare MT5 Data Folder"

if [[ -z "${MT5_TERMINAL_DIR:-}" ]]; then
    # Cauta directoare terminal in AppData/Roaming/MetaQuotes/Terminal/
    MQ_BASE="$WIN_HOME_UNIX/AppData/Roaming/MetaQuotes/Terminal"
    if [[ -d "$MQ_BASE" ]]; then
        # Alege primul director care contine un subfolder MQL5
        for dir in "$MQ_BASE"/*/; do
            if [[ -d "${dir}MQL5" ]]; then
                MT5_TERMINAL_DIR="${dir%/}"
                break
            fi
        done
    fi
fi

if [[ -z "${MT5_TERMINAL_DIR:-}" ]]; then
    WARN "Data Folder MT5 nu a fost detectat automat."
    INFO "Il gasesti in MT5: File > Open Data Folder"
    read -rp "  Introdu calea catre Data Folder: " MT5_TERMINAL_DIR
fi

EXPERTS_DIR="$MT5_TERMINAL_DIR/MQL5/Experts"
INCLUDE_DIR="$MT5_TERMINAL_DIR/MQL5/Include"
LOGS_DIR="$MT5_TERMINAL_DIR/logs"

mkdir -p "$EXPERTS_DIR" "$INCLUDE_DIR"
OK "Data Folder: $MT5_TERMINAL_DIR"
OK "Experts dir: $EXPERTS_DIR"

# =============================================================================
# 5. BACKUP EA EXISTENT
# =============================================================================
HEAD "Backup"

EA_DEST="$EXPERTS_DIR/$EA_FILE"
if [[ -f "$EA_DEST" ]]; then
    BACKUP="$EXPERTS_DIR/${EA_NAME}.bak.$(date +%Y%m%d_%H%M%S).mq5"
    cp "$EA_DEST" "$BACKUP"
    OK "Backup creat: $BACKUP"
else
    INFO "Nu exista versiune anterioara — skip backup."
fi

# =============================================================================
# 6. COPIERE EA
# =============================================================================
HEAD "Copiere $EA_FILE"

cp "$EA_SOURCE" "$EA_DEST"
OK "Copiat: $EA_SOURCE -> $EA_DEST"

# Verifica daca exista si .ex5 compilat anterior (stergem pentru a forta recompilare)
EX5_DEST="$EXPERTS_DIR/${EA_NAME}.ex5"
if [[ -f "$EX5_DEST" ]]; then
    rm -f "$EX5_DEST"
    INFO "Fisier .ex5 anterior sters — va fi recompilat."
fi

# =============================================================================
# 7. COMPILARE CU METAEDITOR
# =============================================================================
HEAD "Compilare cu MetaEditor"

# Converteste cai Unix -> Windows pentru MetaEditor (necesita backslash)
to_win_path() {
    local unixpath="$1"
    if [[ "$SHELL_ENV" == "wsl" ]]; then
        wslpath -w "$unixpath" 2>/dev/null || echo "$unixpath"
    else
        echo "$unixpath" | sed 's|/c/|C:\\|; s|/|\\|g'
    fi
}

WIN_EA_DEST=$(to_win_path "$EA_DEST")
WIN_METAEDITOR=$(to_win_path "$METAEDITOR_EXE")
WIN_INCLUDE=$(to_win_path "$INCLUDE_DIR")

INFO "Compileaza: $WIN_EA_DEST"

# MetaEditor CLI: /compile:"cale" /include:"cale" /log
COMPILE_LOG="$SCRIPT_DIR/compile.log"

if [[ "$SHELL_ENV" == "wsl" ]]; then
    "$METAEDITOR_EXE" \
        /compile:"$WIN_EA_DEST" \
        /include:"$WIN_INCLUDE" \
        /log:"$(to_win_path "$COMPILE_LOG")" \
        2>/dev/null || true
else
    # Git Bash / Cygwin: ruleaza direct
    "$METAEDITOR_EXE" \
        //compile:"$WIN_EA_DEST" \
        //include:"$WIN_INCLUDE" \
        //log:"$(to_win_path "$COMPILE_LOG")" \
        2>/dev/null || true
fi

# Asteapta sa termine compilarea (MetaEditor e async)
INFO "Asteptam compilarea (max 30s)..."
WAIT=0
while [[ ! -f "$EX5_DEST" && $WAIT -lt 30 ]]; do
    sleep 1
    WAIT=$((WAIT+1))
done

if [[ -f "$EX5_DEST" ]]; then
    EX5_SIZE=$(stat -c%s "$EX5_DEST" 2>/dev/null || stat -f%z "$EX5_DEST" 2>/dev/null || echo "?")
    OK "Compilare reusita: ${EA_NAME}.ex5 (${EX5_SIZE} bytes)"
else
    WARN "Fisierul .ex5 nu a fost generat in 30s."
    if [[ -f "$COMPILE_LOG" ]]; then
        WARN "Log compilare:"
        cat "$COMPILE_LOG" | head -30
    fi
    WARN "Poti compila manual: deschide $EA_FILE in MetaEditor > F7"
fi

# Afiseaza erorile/warning-urile din log daca exista
if [[ -f "$COMPILE_LOG" ]]; then
    ERRORS=$(grep -i "error\|warning" "$COMPILE_LOG" 2>/dev/null || true)
    if [[ -n "$ERRORS" ]]; then
        WARN "Erori/Warning-uri compilare:"
        echo "$ERRORS" | while IFS= read -r line; do
            INFO "  $line"
        done
    else
        OK "Niciun error de compilare."
    fi
fi

# =============================================================================
# 8. CONFIGURARE WEBREQUEST (adauga URL-uri in MT5 config)
# =============================================================================
HEAD "Configurare WebRequest URLs"

MT5_CONFIG="$MT5_TERMINAL_DIR/origin.ini"
if [[ ! -f "$MT5_CONFIG" ]]; then
    MT5_CONFIG="$MT5_INSTALL_DIR/terminal64.ini"
fi

URLS=(
    "https://testnet.binancefuture.com"
    "https://api-testnet.bybit.com"
    "https://demo-futures.kraken.com"
)

if [[ -f "$MT5_CONFIG" ]]; then
    INFO "Config MT5: $MT5_CONFIG"
    for url in "${URLS[@]}"; do
        if ! grep -qF "$url" "$MT5_CONFIG" 2>/dev/null; then
            # Agrega URL in sectiunea [WebRequest] sau creeaza sectiunea
            if grep -q "^\[WebRequest\]" "$MT5_CONFIG" 2>/dev/null; then
                sed -i "/^\[WebRequest\]/a URL=$url" "$MT5_CONFIG"
            else
                printf "\n[WebRequest]\nEnabled=1\nURL=%s\n" "$url" >> "$MT5_CONFIG"
            fi
            OK "URL adaugat in config: $url"
        else
            INFO "URL deja prezent: $url"
        fi
    done
else
    WARN "Config MT5 nu a fost gasit — adauga manual URL-urile in:"
    INFO "  MT5 > Tools > Options > Expert Advisors > Allow WebRequest"
    for url in "${URLS[@]}"; do
        INFO "  + $url"
    done
fi

# =============================================================================
# 9. PORNIRE MT5
# =============================================================================
HEAD "Pornire MetaTrader 5"

# Verifica daca MT5 ruleaza deja
MT5_RUNNING=false
if tasklist.exe 2>/dev/null | grep -qi "terminal64\|terminal.exe"; then
    MT5_RUNNING=true
fi

if $MT5_RUNNING; then
    WARN "MT5 este deja pornit."
    read -rp "  Repornesti MT5? (da/nu): " RESTART
    if [[ "$RESTART" =~ ^(da|y|yes)$ ]]; then
        INFO "Oprire MT5..."
        taskkill.exe /IM terminal64.exe /F 2>/dev/null || \
        taskkill.exe /IM terminal.exe   /F 2>/dev/null || true
        sleep 3
        MT5_RUNNING=false
    fi
fi

if ! $MT5_RUNNING; then
    INFO "Pornire: $MT5_EXE"
    if [[ "$SHELL_ENV" == "wsl" ]]; then
        nohup "$MT5_EXE" /portable 2>/dev/null &
    else
        start "" "$MT5_EXE" 2>/dev/null || \
        nohup "$MT5_EXE" 2>/dev/null &
    fi
    sleep 5

    if tasklist.exe 2>/dev/null | grep -qi "terminal64\|terminal.exe"; then
        OK "MetaTrader 5 pornit."
    else
        WARN "Nu s-a putut confirma pornirea MT5 — verifica manual."
    fi
fi

# =============================================================================
# SUMAR
# =============================================================================
echo
echo "============================================================"
echo "  Instalare finalizata — $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo
printf "  %-20s %s\n" "EA sursa:"     "$EA_SOURCE"
printf "  %-20s %s\n" "EA instalat:"  "$EA_DEST"
printf "  %-20s %s\n" "EA compilat:"  "$EX5_DEST"
printf "  %-20s %s\n" "Log compilare:" "$COMPILE_LOG"
echo
echo "  Urmatorii pasi in MT5:"
echo "  1. Navigator (Ctrl+N) > Expert Advisors > QuantumCryptoTrader"
echo "  2. Trage EA pe chart"
echo "  3. Inputs: seteaza ApiKey/SecretKey pentru Binance/Bybit/Kraken"
echo "  4. Bifeaza 'Allow Algo Trading' (buton verde din toolbar)"
echo "  5. Tools > Options > Expert Advisors > Allow WebRequest: verifica URL-urile"
echo
echo "  WebRequest URLs necesare:"
for url in "${URLS[@]}"; do
    printf "    + %s\n" "$url"
done
echo
