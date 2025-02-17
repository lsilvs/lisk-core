#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
#
# LiskHQ/lisk-scripts/lisk_snaphot.sh
# Copyright (C) 2019 Lisk Foundation
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################

# lisk_snapshot.sh creates a blockchain snapshot by stopping the application,
# making a copy of its database, cleaning and dumping/gzip'ing it.
#
# The output directory can be changed by setting the OUTPUT_DIRECTORY
# environement variable, for example:
# ~> OUTPUT_DIRECTORY=/srv/backups ./lisk_snapshot.sh
#
# It is your responsibility to ensure that this script does not get
# started more that once at a time; this can be achieved with e.g.:
# ~> flock --exclusive --nonblock lisk_snapshot.lock ./lisk_snapshot.sh
#
# Periodically deleting old snapshot files is highly recommended;
# this can be achieved with a command like the following:
# ~> find backups/ -type f -ctime 14 -delete

cd "$( cd -P -- "$(dirname -- "$0")" && pwd -P )" || exit 2
# shellcheck source=env.sh
source "$( pwd )/env.sh"

OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY:-$PWD/backups}"
SOURCE_DATABASE=$( node scripts/generate_config.js |jq --raw-output '.components.storage.database' )

mkdir -p "$OUTPUT_DIRECTORY"

function cleanup() {
	dropdb --if-exists lisk_snapshot 2>/dev/null
	bash lisk.sh start_node >/dev/null
	rm -f "$TEMP_FILE"
}

TEMP_FILE=$( mktemp --tmpdir="$OUTPUT_DIRECTORY" )
trap cleanup INT QUIT TERM EXIT

dropdb --if-exists lisk_snapshot 2>/dev/null
bash lisk.sh stop_node >/dev/null
createdb --template="$SOURCE_DATABASE" lisk_snapshot
bash lisk.sh start_node >/dev/null

# The dump file produced by pg_dump does not contain the statistics used by the optimizer to make query planning decisions.
#vacuumdb --analyze --full lisk_snapshot
psql --dbname=lisk_snapshot --command='TRUNCATE peers;' >/dev/null

HEIGHT=$( psql --dbname=lisk_snapshot --tuples-only --command='SELECT height FROM blocks ORDER BY height DESC LIMIT 1;' |xargs)
OUTPUT_FILE="${OUTPUT_DIRECTORY}/${SOURCE_DATABASE}_backup-${HEIGHT}.gz"

pg_dump --no-owner lisk_snapshot |gzip -9 >"$TEMP_FILE"
mv "$TEMP_FILE" "$OUTPUT_FILE"
