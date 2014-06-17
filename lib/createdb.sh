#! /bin/sh
## createdb.sh -- HotCRP database setup
## HotCRP is Copyright (c) 2006-2014 Eddie Kohler and Regents of the UC
## Distributed under an MIT-like license; see LICENSE

export LC_ALL=C LC_CTYPE=C LC_COLLATE=C CONFNAME=
if ! expr "$0" : '.*[/]' >/dev/null; then LIBDIR=./
else LIBDIR=`echo "$0" | sed 's,^\(.*/\)[^/]*$,\1,'`; fi
. ${LIBDIR}dbhelper.sh

help () {
    echo "${LIBDIR}createdb.sh performs MySQL database setup for HotCRP."
    echo
    echo "Usage: ${LIBDIR}createdb.sh [-c CONFIGFILE] [-n CONFNAME] [MYSQLOPTIONS] [DBNAME]"
    echo
    echo "Options:"
    echo "  -c, --config=CONFIG     Configuration file is CONFIG [conf/options.php]."
    echo "      --minimal           Output minimal configuration file."
    echo "      --batch             Batch installation."
    echo "      --replace           Replace existing database and user."
    echo "      --force             Answer yes to all questions."
    echo
    echo "MYSQLOPTIONS are sent to mysql and mysqladmin."
    echo "Common options include '--user=ADMIN_USERNAME' and '--password=ADMIN_PASSWORD'"
    echo "to select a database admin user able to create new tables."
    exit 0
}

usage () {
    echo "Usage: $PROG [MYSQLOPTIONS]" 1>&2
    echo "Type ${LIBDIR}createdb.sh --help for more information." 1>&2
    exit 1
}

PROG=$0
FLAGS=""
MYCREATEDB_USER=""
DBNAME=""
DBUSER=""
PASSWORD=""
distoptions_file=distoptions.php
options_file=
minimal_options=
mycreatedb_args=" --defaults-group-suffix=_hotcrp_createdb"
needpassword=false
force=false
batch=false
replace=false
while [ $# -gt 0 ]; do
    shift=1
    case "$1" in
    -p|--pas|--pass|--passw|--passwo|--passwor|--password)
	needpassword=true;;
    -u|--us|--use|--user)
        MYCREATEDB_USER="$2"; shift;;
    -u*)
        MYCREATEDB_USER="`echo "$1" | sed s/^-u//`";;
    --u=*|--us=*|--use=*|--user=*)
	MYCREATEDB_USER="`echo "$1" | sed 's/^[^=]*=//'`";;
    -p*)
        PASSWORD="`echo "$1" | sed s/^-p//`";;
    --pas=*|--pass=*|--passw=*|--passwo=*|--passwor=*|--password=*)
        PASSWORD="`echo "$1" | sed 's/^[^=]*=//'`";;
    --he|--hel|--help)
	help;;
    --force)
        force=true;;
    --batch)
        batch=true;;
    --minimal)
        minimal_options=y;;
    --replace)
        replace=true;;
    -c|--co|--con|--conf|--confi|--config|-c*|--co=*|--con=*|--conf=*|--confi=*|--config=*)
        parse_common_argument "$@";;
    -n|--n|--na|--nam|--name|-n*|--n=*|--na=*|--nam=*|--name=*)
        parse_common_argument "$@";;
    --defaults-group-suffix=*)
        mycreatedb_args=; FLAGS="$FLAGS '$1'";;
    -*)
	FLAGS="$FLAGS '$1'";;
    *)
	if [ -z "$DBNAME" ]; then DBNAME="$1"; else usage; fi;;
    esac
    shift $shift
done

### Test mysql binary
check_mysqlish MYSQL mysql
check_mysqlish MYSQLADMIN mysqladmin

# attempt to secure password handling
# (It is considered insecure to supply a MySQL password on the command
# line; in some MySQL versions it actually generates a warning.)
if $needpassword; then
    echo_n "Enter MySQL password: "
    stty -echo; trap "stty echo; exit 1" INT
    read PASSWORD
    stty echo; trap - INT
    echo
fi
set_myargs "$MYCREATEDB_USER" "$PASSWORD"


if ! (echo 'show databases;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS >/dev/null); then
    echo 1>&2
    echo "* Could not run $MYSQL $myargs_redacted $FLAGS. Did you enter the right password?" 1>&2
    echo 1>&2
    exit 1
fi
grants=`echo 'show grants;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS | grep -i -e create -e all | grep -i 'on \*\.\*'`
if ! $force && test -z "$grants"; then
    echo 1>&2
    echo "* This account doesn't appear to have the privilege to create MySQL databases." 1>&2
    echo "* Try 'sudo $PROG' and/or supply '--user' and '--password' options." 1>&2
    echo "* If you think this message is in error, run '$PROG --force'." 1>&2
    echo 1>&2
    exit 1
fi


echo "Creating the database and database user for your conference."
echo "Access is allowed only from the local host."
echo

echo_dbname () {
    cat <<__EOF__
$DBNAME
__EOF__
}

batch_fail () {
    if $batch; then
        echo 1>&2
        echo "* Giving up. Try '--batch --replace' or other arguments and try again." 1>&2
        echo 1>&2
        exit 1
    fi
}

default_dbname=
x="`getdbopt dbName 2>/dev/null`"
x="`eval "echo $x"`"
if test -n "$x"; then
    bad="`eval "echo $x" | tr -d a-zA-Z0-9_.-`"
    if test -z "$bad"; then default_dbname="`echo $x`"; fi
fi

while true; do
    if $batch; then echo_n "Database"; else echo_n "Enter database name (NO SPACES)"; fi
    if [ -z "$DBNAME" ]; then
	test -n "$default_dbname" && echo_n " [default $default_dbname]"
	echo_n ": "
	read -r DBNAME
    else
	echo ": $DBNAME"
    fi

    test -z "$DBNAME" -a -n "$default_dbname" && DBNAME="$default_dbname"
    x="`echo_dbname | tr -d a-zA-Z0-9_.-`"
    c="`echo_dbname | wc -c`"
    if test -z "$DBNAME"; then
	echo "* Quitting." 1>&2
	exit 1
    elif test -n "$x"; then
	echo "* The database name must only contain characters in [-.a-zA-Z0-9_]." 1>&2
    elif test "$c" -gt 64; then
	echo "* The database name can be at most 64 characters long." 1>&2
    elif test "`echo "$DBNAME" | head -c 1`" = "."; then
	echo "* The database name must not start with a period." 1>&2
    elif test "$DBNAME" = mysql || expr "$DBNAME" : '.*_schema$' >/dev/null; then
	echo "* Database name '$DBNAME' is reserved." 1>&2
    else
	break
    fi

    DBNAME=
    batch_fail
done


echo_dbpass () {
    cat <<__EOF__
$DBPASS
__EOF__
}

default_dbpass=
x="`getdbopt dbPassword 2>/dev/null`"
x="`eval "echo $x"`"
test -n "$x" -a "$DBNAME" = "$default_dbname" && default_dbpass="$x"
if test -n "$default_dbpass"; then
    default_dbpass_description="taken from `findoptions`"
else
    default_dbpass=`generate_random_ints | generate_password 12`
    default_dbpass_length="`echo_n "$default_dbpass" | wc -c`"
    default_dbpass_description="is `echo $default_dbpass_length` random characters"
fi
while true; do
    if ! $batch; then
        echo_n "Enter password for mysql user $DBNAME [default $default_dbpass_description]: "
        stty -echo; trap "stty echo; exit 1" INT
        read -r DBPASS
        stty echo; trap - INT
    else
        DBPASS=
    fi
    if [ -z "`echo_dbpass`" ]; then DBPASS=$default_dbpass; fi
    x=`echo_dbpass | tr -d -c '\000'"'"`
    if test -z "$x" >/dev/null; then break; fi
    echo 1>&2
    echo "* The database password must not contain single quotes or null characters." 1>&2
    batch_fail
done
$batch || echo

sql_dbpass () {
    echo_dbpass | sql_quote
}

php_dbpass () {
    echo_dbpass | sed -e 's,\([\\"'"'"']\),\\\1,g'
}


DBNAME_QUOTED=`echo "$DBNAME" | sed 's/[.]/[.]/g'`
echo
echo "+ echo 'show databases;' | $MYSQL$mycreatedb_args$myargs_redacted$FLAGS -N | grep '^$DBNAME_QUOTED\$'"
echo 'show databases;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS -N >/dev/null || exit 1
echo 'show databases;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS -N | grep "^$DBNAME_QUOTED\$" >/dev/null 2>&1
dbexists="$?"

test -z "$DBUSER" && DBUSER="$DBNAME"
DBUSER_QUOTED=`echo "$DBUSER" | sed 's/[.]/[.]/g'`
echo "+ echo 'select User from user group by User;' | $MYSQL$mycreatedb_args$myargs_redacted$FLAGS -N mysql | grep '^$DBUSER_QUOTED\$'"
echo 'select User from user group by User;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS -N mysql >/dev/null || exit 1
echo 'select User from user group by User;' | eval $MYSQL $mycreatedb_args $myargs $FLAGS -N mysql | grep "^$DBUSER_QUOTED\$" >/dev/null 2>&1
userexists="$?"
createdbuser=y
if [ "$dbexists" = 0 -o "$userexists" = 0 ]; then
    echo
    test "$dbexists" = 0 && echo "A database named '$DBNAME' already exists!"
    test "$userexists" = 0 && echo "A user named '$DBUSER' already exists!"
    while ! $replace; do
        batch_fail
	echo_n "Replace? [Y/n] "
	read createdbuser
	expr "$createdbuser" : "[ynqYNQ].*" >/dev/null && break
	test -z "$createdbuser" && break
    done
    expr "$createdbuser" : "[qQ].*" >/dev/null && echo "Exiting" && exit 0
    expr "$createdbuser" : "[nN].*" >/dev/null || createdbuser=y

    if [ "$createdbuser" = y -a "$dbexists" = 0 ]; then
	echo "+ $MYSQLADMIN$mycreatedb_args$myargs_redacted$FLAGS -f drop $DBNAME"
	eval $MYSQLADMIN $mycreatedb_args $myargs $FLAGS -f drop $DBNAME || exit 1
    fi
fi
if [ "$createdbuser" = y ]; then
    echo
    echo "Creating $DBNAME database..."
    echo "+ $MYSQLADMIN$mycreatedb_args$myargs_redacted$FLAGS --default-character-set=utf8 create $DBNAME"
    eval $MYSQLADMIN $mycreatedb_args $myargs $FLAGS --default-character-set=utf8 create $DBNAME || exit 1

    echo "Creating $DBUSER user and password..."
    eval $MYSQL $mycreatedb_args $myargs $FLAGS mysql <<__EOF__ || exit 1
DELETE FROM user WHERE user='$DBUSER';
DELETE FROM db WHERE db='$DBNAME';
FLUSH PRIVILEGES;

CREATE USER '$DBUSER'@'localhost' IDENTIFIED BY '`sql_dbpass`',
    '$DBUSER'@'127.0.0.1' IDENTIFIED BY '`sql_dbpass`',
    '$DBUSER'@'localhost.localdomain' IDENTIFIED BY '`sql_dbpass`';

INSERT INTO db SET
    Host='127.0.0.1',
    Db='$DBNAME',
    User='$DBUSER',
    Select_priv='Y',
    Insert_priv='Y',
    Update_priv='Y',
    Delete_priv='Y',
    Create_priv='Y',
    Drop_priv='Y',
    Index_priv='Y',
    References_priv='Y',
    Alter_priv='Y',
    Lock_tables_priv='Y',
    Create_tmp_table_priv='Y';

INSERT INTO db SET
    Host='localhost.localdomain',
    Db='$DBNAME',
    User='$DBUSER',
    Select_priv='Y',
    Insert_priv='Y',
    Update_priv='Y',
    Delete_priv='Y',
    Create_priv='Y',
    Drop_priv='Y',
    Index_priv='Y',
    References_priv='Y',
    Alter_priv='Y',
    Lock_tables_priv='Y',
    Create_tmp_table_priv='Y';

INSERT INTO db SET
    Host='localhost',
    Db='$DBNAME',
    User='$DBUSER',
    Select_priv='Y',
    Insert_priv='Y',
    Update_priv='Y',
    Delete_priv='Y',
    Create_priv='Y',
    Drop_priv='Y',
    Index_priv='Y',
    References_priv='Y',
    Alter_priv='Y',
    Lock_tables_priv='Y',
    Create_tmp_table_priv='Y';

__EOF__
##

    echo_n "Granting RELOAD privilege..."
    eval $MYSQL $mycreatedb_args $myargs $FLAGS mysql <<__EOF__ || echo_n " FAILED!"
GRANT RELOAD ON *.* TO '$DBUSER'@'localhost', '$DBUSER'@'127.0.0.1', '$DBUSER'@'localhost.localdomain';
__EOF__
    echo

    echo "Reloading grant tables..."
    eval $MYSQLADMIN $mycreatedb_args $myargs $FLAGS reload || exit 1

    if [ ! -r "${SRCDIR}schema.sql" ]; then
	echo 1>&2
        echo "* Can't read schema.sql! You'll have to populate the database yourself." 1>&2
        echo 1>&2
	exit 1
    fi
else
    echo
    echo "Continuing with existing database and user."
fi

##
## Populate the database schema
##
populatedb=y
if ! $replace && test "$createdb" = n; then
    batch_fail
    echo
    echo "Do you want to replace the current database contents with a fresh install?"
    while true; do
        echo_n "Replace database contents? [Y/n] "
        read populatedb
        expr "$populatedb" : "[ynqYNQ].*" >/dev/null && break
        test -z "$populatedb" && break
    done
    expr "$populatedb" : "[qQ].*" >/dev/null && echo "Exiting..." && exit 0
    expr "$populatedb" : "[nN].*" >/dev/null || populatedb=y
    echo
fi
if [ "$populatedb" = y ]; then
    echo "Populating database..."
    set_myargs "$DBUSER" "`echo_dbpass`"
    echo "+ $MYSQL$myargs_redacted$FLAGS $DBNAME < ${SRCDIR}schema.sql"
    eval $MYSQL $myargs $FLAGS $DBNAME < ${SRCDIR}schema.sql || exit 1
fi

##
## Create options.php
##

create_options () {
    test -n "$minimal_options" && echo '<?php
global $Opt;'
    test -z "$minimal_options" && awk 'BEGIN { p = 1 }
/^\$Opt\[.db/ { p = 0 }
{ if (p) print }' < "${SRCDIR}${distoptions_file}"
    cat <<__EOF__
\$Opt["dbName"] = "$DBNAME";
\$Opt["dbUser"] = "$DBUSER";
\$Opt["dbPassword"] = "`php_dbpass`";
__EOF__
    test -z "$minimal_options" && awk 'BEGIN { p = 0 }
/^\$Opt\[.db/ { p = 1; next }
/^\$Opt\[.passwordHmacKey/ { p = 0; next }
{ if (p) print }' < "${SRCDIR}${distoptions_file}"
    cat <<__EOF__
\$Opt["passwordHmacKey"] = "`generate_random_ints | generate_password 40`";
__EOF__
    test -z "$minimal_options" && awk 'BEGIN { p = 0 }
/^\$Opt\[.passwordHmacKey/ { p = 1; next }
{ if (p) print }' < "${SRCDIR}${distoptions_file}"
}

is_group_member () {
    u="$1"; g="$2"
    if test -x /usr/bin/dsmemberutil; then
	if expr "$u" : '[0-9]*$' >/dev/null; then ua="-u"; else ua="-U"; fi
	if expr "$g" : '[0-9]*$' >/dev/null; then ga="-g"; else ga="-G"; fi
	/usr/bin/dsmemberutil checkmembership $ua "$u" $ga "$g" 2>/dev/null | grep "is a member" >/dev/null
    else
	members="`grep "^$group" /etc/group | sed 's/.*:.*:.*:/,/'`"
	echo "$members," | grep ",$u," >/dev/null
    fi
}

expected_options="`findoptions expected`"
current_options="`findoptions`"
if findoptions >/dev/null; then
    echo
    echo "* Your $current_options file already exists."
    echo "* Edit it to use the database name, username, and password you chose."
    if [ "$current_options" != "$expected_options" ]; then
        echo
        echo "* Also, the new location for the options file is $expected_options."
        echo "* You should move $current_options there."
    fi
    echo
elif [ -r "${SRCDIR}${distoptions_file}" -o -n "$minimal_options" ]; then
    echo
    echo "Creating $expected_options..."
    create_options > "$expected_options"
    if [ -n "$SUDO_USER" ]; then
	echo + chown $SUDO_USER "$expected_options"
	chown $SUDO_USER "$expected_options"
    fi
    chmod o-rwx "$expected_options"
    current_options="$expected_options"
else
    echo
    echo "* Not creating $expected_options."
    current_options=
fi

if test -n "$current_options"; then
    # warn about unreadable options file
    group="`ls -l "$current_options" | awk '{print $4}'`"

    httpd_user="`ps axho user,comm | grep -E 'httpd|apache' | uniq | grep -v root | awk 'END {if ($1) print $1}'`"

    if test -z "$httpd_user"; then
	echo
	echo "* The $current_options file contains sensitive data."
	echo "* You may need to change its group so the Web server can read it."
	echo
    elif ! is_group_member "$httpd_user" "$group"; then
	if [ -n "$SUDO_USER" ] && chgrp "$httpd_user" "$current_options" 2>/dev/null; then
	    echo "Making $current_options readable by the Web server..."
	    echo + chgrp "$httpd_user" "$current_options"
	else
	    echo
	    echo "* The $current_options file contains important data, but the Web server"
	    echo "* cannot read it. Use 'chgrp GROUP $current_options' to change its group."
	    echo
	fi
    fi
fi

test -n "$PASSWORDFILE" && rm -f "$PASSWORDFILE"
