# Función para iniciar o atachar tmux con nombre de sesión según el proyecto

# Redefinir el comando tmux para que use la lógica de sesión automáticamente
tmux() {
  if [ "$#" -eq 0 ]; then
    if [ -d .git ]; then
      SESSION_NAME=$(basename "$PWD")
    else
      SESSION_NAME="session-$(basename "$PWD")-$(date +%Y%m%d-%H%M%S)"
    fi
    command tmux attach -t "$SESSION_NAME" 2>/dev/null || command tmux new-session -s "$SESSION_NAME"
  else
    command tmux "$@"
  fi
}
eval "$(/opt/homebrew/bin/brew shellenv)"
PATH=~/.console-ninja/.bin:$PATH

export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh"

nvm use default &> /dev/null

if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi

export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH

# Android SDK (ruta típica en Apple Silicon)
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/tools/bin
export PATH=$PATH:$ANDROID_HOME/platform-tools

# ignorar ctrl + d para cerrar terminal
setopt ignoreeof

# TMUX
# ==========================================
if [ -z "$TMUX_SESSION_START_DIR" ]; then
  export TMUX_SESSION_START_DIR="$PWD"
fi

if [ -d .git ]; then
  SESSION_NAME=$(basename "$PWD")
else
  SESSION_NAME="session-$(basename "$PWD")-$(date +%Y%m%d-%H%M%S)"
fi
# ==========================================
. "$HOME/.local/bin/env"
export PATH="$PATH:$HOME/.local/bin"

. "$HOME/.local/bin/env"
export PATH="$PATH:$HOME/.local/bin"

# Powerlevel10k (sourcing file managed in repo)
if [ -f "$HOME/.p10k.zsh" ]; then
  source "$HOME/.p10k.zsh"
fi

# Zsh plugins (installed by setup.sh into ~/.local/share)
ZSH_LOCAL="$HOME/.local/share/zsh"
if [ -d "$ZSH_LOCAL/zsh-autosuggestions" ]; then
  source "$ZSH_LOCAL/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [ -d "$ZSH_LOCAL/zsh-syntax-highlighting" ]; then
  source "$ZSH_LOCAL/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# Clipboard helpers (win32yank/xclip/xsel) prefer CLI tools; setup.sh will install xclip/xsel on Linux
# Use clipboard integration in tmux and Neovim via system clipboard
