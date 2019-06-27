#!/usr/bin/env sh

# Switch to directory the script resides in
SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
cd $SCRIPTPATH

# move to the top level analysis directory
cd ..
cd ..

# if the lib directory does not exist, error
if ! [ -d "lib" ]; then
  echo "ERROR: lib file not uploaded."
  exit 1
fi

# if the example.rb file does not exist, error, otherwise execute it
if [ -f "lib/example.rb" ]; then
  echo "Executing the example.rb file."
  ruby lib/example.rb
else
  echo "ERROR: lib/example.rb not uploaded."
  exit 1
fi