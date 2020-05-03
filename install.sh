#!/bin/bash

echo "------------------------"
echo "Welcome. You're going to install the amazing Vim distribution Onesimos!"
echo "------------------------"

# Ask for alternative root directory
echo "Install in the home directory?"

while true; do
        read -n 1 -p "(<Enter> to confirm)" key

        # if empty (Enter)
        if [[ -z "$key" ]]; then
                VIMRCDIR="$HOME"

        # else ask for a path
        else
                echo ""
                read -p "Enter an alternative path: " VIMRCDIR
        fi

        if [ -d "$VIMRCDIR" ]; then
                echo -e "\nThe vimrc path is going to be $VIMRCDIR"
                break
        else
                echo "The given directory doesn't exist."

                select yn in Yes No; do
                        case $yn in
                                Yes ) mkdir "$VIMRCDIR"\;break;break;;
                                No ) echo "Restarting ...";break;;
                        esac
                done
        fi
done

# Cloning Repo from GitHub
cd $VIMRCDIR
echo -e "\nCloning the repository on GitHub ..."
git clone https://github.com/BaksiLi/Onesimos ./vimrc

MYVIMRC="$VIMRCDIR/vimrc"
# TODO: check message

# Checking old .vimrc file
echo -e "\nChecking old .vimrc file ..."
if test -f ".vimrc"; then
        echo "Found!"
        _oldrc="$VIMRCDIR/.vimrc"
        _newrc="$MYVIMRC/vimrc.backup"
        echo "Moving it to $MYVIMRC/vimrc.backup"
        mv $_oldrc $_newrc
fi
echo "Done."

# Create new .vimrc file
echo -e "\nCreating new .vimrc"
touch "$VIMRCDIR/.vimrc"
cat >> "$VIMRCDIR/.vimrc" << EOL
"return" 2>&- || "exit"

let \$VIMRCDIR = '$MYVIMRC'
let \$MYVIMDOT = \$VIMRCDIR.'/init.vim'

if filereadable(glob(\$MYVIMDOT))
    source \$MYVIMDOT
else
    echomsg 'Vim configuration folder not found!'
endif
EOL

# TODO: verification
read -n 1 -s -r -p "Installation Complete!"
echo ""
