#!/bin/bash

# Print Onesimos logo.
cat << "EOF"
         .-://:-.      `:`
      .+syyyyyyyys+.  :ooo/`
     /yyyyyyyyyyyyyy+``/oooo/`
    +yys+++++oooooooy+  /ooooo/````````````..
   `yyy/...``````...sy. .ooooo/...```````..`
   `yyyyss+``````sssyy. .oooooo++:`````..`
    +yyyyy+``````syyy+  :ooooo+:.````..`
    `+yyyy+``````syy+` -oooo+:.````.:+/.
      .+sy+``````o+. `:ooo+:.````.:+ooo+/.
   `::.``.:``````-`./+oo+:.````.:+ooooooo+/.
  -+ooo+/::``````++ooo+:.````.:+ooooooooooo+/.
  `-+ooooo/``````+oo+:.````.:+oooooooooooooo+/`
    `-+ooo/``````++:.````.:+oooooooooooooo+:.
      `-+o/``````-.````.:+oooooooooooooo+:`
        `-:``````````.:+oooooooooooooo+-`
          -````````.:+oooooooooooooo/-`
          -``````.:+oooooooooooooo/.
          -````.:+ooooooooooooo+:`
          -``..``-+oooooooooo+:`
          -..`    `-+oooooo+-`
          -`         -+oo/.
                       -.
EOF

echo "------------------------"
echo "Welcome. You're going to install the amazing Onesimos Vim configuration!"
echo "------------------------"

# Checking for git and vim
echo -e "\nChecking the required environment..."
if [[ -x "$(command -v vim)" && -x "$(command -v git)" ]]; then
        echo "Done."
else
        echo "Please check if you have vim and git installed."
        exit
fi

# Ask for alternative root directory
echo -e "\nInstall in the home directory?"

while true; do
        read -n 1 -p "(<Enter> to confirm)" key

        # if empty (Enter)
        if [[ -z "$key" ]]; then
                VIMRCDIR="$HOME"

        # else ask for a path
        else
                echo ""
                read -p "Enter an alternative path: " VIMRCDIR
                VIMRCDIR=${VIMRCDIR/#\~/$HOME}  # replace tilde with $HOME
        fi

        if [ -d "${VIMRCDIR}" ]; then
                echo -e "\nThe vimrc path is going to be $VIMRCDIR"
                break
        else
                echo -e "The given directory doesn't exist.\nCreate?"

                select yn in Yes No; do
                        case $yn in
                                Yes ) mkdir "$VIMRCDIR";break;break;;
                                No ) echo "Restarting...";break;;
                        esac
                done
        fi
done

# Cloning Repo from GitHub
cd $VIMRCDIR || exit
MYVIMRC="${VIMRCDIR%/}/vimrc"
echo -e "\nCloning the repository on GitHub..."
git clone https://github.com/BaksiLi/Onesimos ./vimrc && echo "Done." || (cd $MYVIMRC && git pull)

# Install Onesimos Functions
# Once they are ready...

# Checking old .vimrc file
echo -e "\nChecking old .vimrc file..."
if test -f ".vimrc"; then
        echo "Found!"
        _oldrc="$HOME/.vimrc"
        _newrc="$MYVIMRC/vimrc.backup"
        echo "Moving it to $MYVIMRC/vimrc.backup"
        mv "$_oldrc" "$_newrc"
fi
echo "Done."

# Create new .vimrc file
echo -e "\nCreating new .vimrc"
touch "$HOME/.vimrc"
cat >> "$HOME/.vimrc" << EOL
"return" 2>&- || "exit"

let \$VIMRCDIR = '$MYVIMRC'
let \$MYVIMDOT = \$VIMRCDIR.'/init.vim'

if filereadable(glob(\$MYVIMDOT))
    source \$MYVIMDOT
else
    echomsg 'Vim configuration folder not found!'
endif
EOL
[ -f "$HOME/.vimrc" ] && echo "Done." || exit

# TODO: verification
echo ""
read -n 1 -s -r -p "Installation Complete!"

# if echo $EDITOR not vim, ask
# export EDITOR=vim

echo -e "\nLaunching Vim..."
vim -c "PlugInstall"
