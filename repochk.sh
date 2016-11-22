#!/bin/sh
#
# This script could be used as a pre-commit hook.
# It makes sure that the README.md file is generated from the
# assist.sh source.
#
# Just execute from the directory where assist.sh is placed.
#

#
# Function to modify files in-place
#
fixfile() {
  local FILTER=no

  while [ $# -gt 0 ]
  do
    case "$1" in
	--filter)
	    FILTER=yes
	    ;;
	-*)
	    echo "Invalid option: $1" 1>&2
	    return 1
	    ;;
	*)
	    break
	    ;;
    esac
    shift
  done

  if [ $# -eq 0 ] ; then
    echo "No file specified" 1>&2
    return 1
  elif [ $# -gt 1 ] ; then
    echo "Ignoring additional options: $*" 1>&2
  fi

  local FILE="$1"

  local OTXT=""
  if [ -f $FILE ] ; then
    OTXT=$(sed 's/^/:/' $FILE)
  fi

  if [ $FILTER = yes ] ; then
    # Stdin is not contents but actually is a filter script
    local INCODE="$(cat)"
    if [ -f $FILE ] ; then
      local NTXT="$(cat $FILE)"
    else
      local NTXT=""
    fi
    local NTXT=$(echo "$NTXT" | (eval "$INCODE" )| sed 's/^/:/' )
  else
    local NTXT=$(sed 's/^/:/')
  fi
  
  if [ x"$OTXT" != x"$NTXT" ] ; then
    sed 's/^://' > $FILE <<<"$NTXT"
    echo $FILE updated 1>&2
    return 1
  else
    return 0
  fi
}

ver() {
  desc=$(git describe)
  branch_name=$(git symbolic-ref -q HEAD)
  branch_name=${branch_name##refs/heads/}
  branch_name=${branch_name:-HEAD}
  if [ "master" = "$branch_name" ] ; then
    branch_name=""
    desc=$(sed -e 's/-.*//' <<<"$desc")
  else
    branch_name=":$branch_name"
  fi
  echo $desc$branch_name
}

if [ $# -gt 0 ] ; then
  case "$1" in
    ver)
      ver
      ;;
    bumpver)
      if [ $# -eq 1 ] ; then
	ver=$(ver)
      else
	ver=$2
      fi
      ( sed 's/^ver=.*/ver='$ver'/' assist.sh | fixfile assist.sh ) \
	  || echo "Bumped to version $ver"
  esac
  exit
fi


[ -d ".git" ] || ( echo "Not in a GIT repo" ; exit 1) || exit 1

ret=0
[ ! -f .git/hooks/pre-commit ] && ln -s ../../repochk.sh .git/hooks/pre-commit
( sh assist.sh doc text | fixfile README.md ) || ret=1
if [ $ret -ne 0 ] ;then
  echo "Files updated, pre-commit aborted"
fi
exit $ret



