#!/bin/sh

set -Eeu

function print_help ()
{
    #echo "Usage: kf2.sh {start|stop|restart|status|update [preview]|log|config|purge <map_id>|init|help}"
    echo "killinuxfloor - Killing Floor 2 Linux Server Installer and Manager (c) noobient"
    echo ""
    echo "Usage:"
    echo "------"
    echo -e "kf2.sh init \t\t populate all internal KF2 server settings with defaults (don't forget to run 'config' afterwards)"
    echo -e "kf2.sh config \t\t apply your own settings to the internal KF2 server config"
    echo -e "kf2.sh start \t\t start KF2"
    echo -e "kf2.sh stop \t\t stop KF2"
    echo -e "kf2.sh restart \t\t restart KF2"
    echo -e "kf2.sh status \t\t query the status of KF2"
    echo -e "kf2.sh log \t\t display the KF2 logs"
    echo -e "kf2.sh purge <map_id> \t remove an installed workshop map"
    echo -e "kf2.sh update \t\t check for and apply KF2 updates (don't forget to run 'init' and 'config' if update found)"
    echo -e "kf2.sh update preview \t apply updates from the 'preview' branch"
    echo -e "kf2.sh info \t\t show KF2 installation info"
    echo -e "kf2.sh verify \t\t verify integrity of KF2 files"
    echo -e "kf2.sh help \t\t print this help"
}

function errorexit ()
{
    case $? in
        1)
            print_help
            ;;

        2)
            echo -e "\e[31merror!\e[0m"
            ;;

    esac
}

trap errorexit EXIT

# variables
LIVE_CONF="${HOME}/Steam/KF2Server/KFGame/Config"
OWN_CONF="${HOME}/Config"
MAP_DIR="${HOME}/Steam/KF2Server/KFGame/BrewedPC/Maps"
MAP_LIST="${OWN_CONF}/My-Maps.csv"
MUTATOR_LIST="${OWN_CONF}/My-Mutators.csv"
CYCLE_LIST="${OWN_CONF}/My-Cycles.csv"

ECHO_DONE='echo -e \e[32mdone\e[0m.'

function sanitize_conf ()
{
    # cleanup
    echo -n 'Making sure INI files are formatted properly... '
    for INI in 'LinuxServer-KFEngine.ini' 'LinuxServer-KFGame.ini'
    do
        # delete repeated newlines
        cp ${LIVE_CONF}/${INI} ${LIVE_CONF}/${INI}.tmp
        cat -s ${LIVE_CONF}/${INI}.tmp > ${LIVE_CONF}/${INI}
        rm ${LIVE_CONF}/${INI}.tmp

        # get rid of spaces around = added by crudini
        sed -i 's/ = /=/' ${LIVE_CONF}/${INI}
    done
    ${ECHO_DONE}
}

function add_mutators ()
{
    # parse mutator list
    echo -n 'Applying mutators... '
    test -e ${MUTATOR_LIST} || exit 2
    while read -r line
    do
        # skip comments
        [[ $line = \#* ]] && continue

        # add entry to workshop list, can't use crudini here because parameters aren't unique
        echo "ServerSubscribedWorkshopItems=${line}" >> ${LIVE_CONF}/LinuxServer-KFEngine.ini
    done < ${MUTATOR_LIST}
    ${ECHO_DONE}
}

function regen_conf ()
{
    # merge live ini files with own custom values
    # these must be unique for crudini to work
    # the rest will be generated by this script
    echo -n 'Applying settings to upstream config files... '
    for f in $(find -L ${OWN_CONF} -maxdepth 1 -name '*.ini' -type f -printf %f\\n)
    do
        crudini --merge "${LIVE_CONF}/${f#$"My-"}" < "${OWN_CONF}/${f}"
    done
    ${ECHO_DONE}

    # delete old workshop section from KFEngine altogether
    echo -n 'Deleting old workshop entries... '
    crudini --del ${LIVE_CONF}/LinuxServer-KFEngine.ini OnlineSubsystemSteamworks.KFWorkshopSteamworks
    # workshop header
    echo '[OnlineSubsystemSteamworks.KFWorkshopSteamworks]' >> ${LIVE_CONF}/LinuxServer-KFEngine.ini
    ${ECHO_DONE}

    # also reset download managers, we need multiple values and in specific order
    echo -n 'Configuring map download managers... '
    crudini --del ${LIVE_CONF}/LinuxServer-KFEngine.ini IpDrv.TcpNetDriver DownloadManagers
    crudini --set ${LIVE_CONF}/LinuxServer-KFEngine.ini IpDrv.TcpNetDriver DownloadManagers OnlineSubsystemSteamworks.SteamWorkshopDownload
    sed -i 's/DownloadManagers.*=.*OnlineSubsystemSteamworks.SteamWorkshopDownload/&\nDownloadManagers=IpDrv.HTTPDownload/' ${LIVE_CONF}/LinuxServer-KFEngine.ini
    ${ECHO_DONE}

    # delete old cycles
    echo -n 'Deleting old game cycles... '
    crudini --del ${LIVE_CONF}/LinuxServer-KFGame.ini KFGame.KFGameInfo GameMapCycles
    ${ECHO_DONE}

    # cycle string
    CYCLE_START='GameMapCycles=(Maps=('

    # parse custom cycle list
    echo -n 'Adding custom game cycles... '
    test -e ${CYCLE_LIST} || exit 2
    while read -r line
    do
        # skip comments
        [[ $line = \#* ]] && continue
        CYCLE="${CYCLE_START}\"${line}\"))"
        CYCLE=$(sed 's/,/","/g' <<< ${CYCLE})
        sed -i "s/\[KFGame.KFGameInfo\]/&\n${CYCLE}/" ${LIVE_CONF}/LinuxServer-KFGame.ini
    done < ${CYCLE_LIST}
    ${ECHO_DONE}

    # cycle string reset
    CYCLE="${CYCLE_START}"
    # track if we need a comma or not
    FIRST=1

    # parse map list
    echo -n 'Applying workshop subscriptions and updating webadmin map entries... '
    test -e ${MAP_LIST} || exit 2
    while read -r line
    do
        # skip comments
        [[ $line = \#* ]] && continue
        ID=$(awk -F "," '{print $1}' <<< ${line})
        NAME=$(awk -F "," '{print $2}' <<< ${line})

        # add entry to workshop list, can't use crudini here because parameters aren't unique
        echo "ServerSubscribedWorkshopItems=${ID}" >> ${LIVE_CONF}/LinuxServer-KFEngine.ini

        # delete old entry from KFGame list to make sure all custom entries are at the end
        crudini --del ${LIVE_CONF}/LinuxServer-KFGame.ini "${NAME} KFMapSummary"

        # add new entry to KFGame list
        crudini --set ${LIVE_CONF}/LinuxServer-KFGame.ini "${NAME} KFMapSummary" "MapName" "${NAME}"

        # construct the workshop map cycle
        if [ ${FIRST} -ne 1 ]
        then
            CYCLE="${CYCLE},"
        fi
        CYCLE="${CYCLE}\"${NAME}\""
        FIRST=0
    done < ${MAP_LIST}
    ${ECHO_DONE}

    # write the workshop map cycle
    echo -n 'Adding map cycle for workshop maps... '
    CYCLE="${CYCLE}))"
    sed -i "s/\[KFGame.KFGameInfo\]/&\n${CYCLE}/" ${LIVE_CONF}/LinuxServer-KFGame.ini
    ${ECHO_DONE}

    # reset
    CYCLE="${CYCLE_START}"
    FIRST=1

    # cycle for stock maps
    echo -n 'Adding map cycle for stock maps... '
    for d in $(find ${MAP_DIR} -maxdepth 1 -mindepth 1 -type d -printf %f\\n | sort)
    do
        if [ ${FIRST} -ne 1 ]
        then
            CYCLE="${CYCLE},"
        fi
        CYCLE="${CYCLE}\"KF-${d}\""
        FIRST=0
    done

    # always do default maps last so that it is the first cycle in the config
    CYCLE="${CYCLE}))"
    sed -i "s/\[KFGame.KFGameInfo\]/&\n${CYCLE}/" ${LIVE_CONF}/LinuxServer-KFGame.ini
    ${ECHO_DONE}

    add_mutators

    sanitize_conf

    echo 'Killing Floor 2 server configuration regenerated successfully!'
}

function purge_map ()
{
    echo "Purging map with ID ${1}... "

    echo -n 'Finding map name corresponding to ID... '
    MAP_NAME=$(grep ^${1} ${MAP_LIST} | cut -d',' -f2)
    echo "${MAP_NAME}."

    echo -n 'Deleting from KFGame.ini... '
    crudini --del ${LIVE_CONF}/LinuxServer-KFGame.ini "${MAP_NAME} KFMapSummary"
    ${ECHO_DONE}

    echo -n 'Deleting from KFEngine.ini... '
    sed -i "/ServerSubscribedWorkshopItems=${1}/d" ${LIVE_CONF}/LinuxServer-KFEngine.ini
    ${ECHO_DONE}

    echo -n 'Deleting from My-Maps.csv... '
    sed -i --follow-symlinks "/^${1},${MAP_NAME}/d" ${OWN_CONF}/My-Maps.csv
    ${ECHO_DONE}

    echo 'Performing complete config regeneration... '
    regen_conf

    echo -n 'Deleting map files from workshop and cache... '
    rm -rf "${HOME}/Cache/${1}"
    rm -rf "${HOME}/Workshop/content/232090/${1}"
    sed -i "/${1}/,+5d" "${HOME}/Workshop/appworkshop_232090.acf"
    ${ECHO_DONE}

    echo "The ${MAP_NAME} map with ID ${1} has been completely purged."
}

function start_kf2 ()
{
    sudo /bin/systemctl start kf2.service
}

function stop_kf2 ()
{
    sudo /bin/systemctl stop kf2.service
}

function init_kf2 ()
{
    stop_kf2
    rm -f ${LIVE_CONF}/KF*.ini
    rm -f ${LIVE_CONF}/LinuxServer-*.ini
    start_kf2
    echo -n 'Waiting for default INI files to be generated... '
    sleep 20
    ${ECHO_DONE}
    stop_kf2
}

function update_kf2 ()
{
    # hack: gotta use -beta without a branch name to force non-beta
    # https://forums.tripwireinteractive.com/forum/killing-floor-2/kf2-news-and-announcements/news-and-announcements-af/2321016-summer-sideshow-2018-treacherous-skies?p=2321049#post2321049
    case $# in
        0)
            steamcmd.sh +login anonymous +force_install_dir ./KF2Server +app_update 232130 -beta +exit
            ;;

        1)
            steamcmd.sh +login anonymous +force_install_dir ./KF2Server +app_update 232130 -beta $1 +exit
            ;;
    esac
}

function get_install ()
{
    steamcmd.sh +login anonymous +force_install_dir ./KF2Server +app_status 232130 +exit
}

function check_integrity ()
{
    case $# in
        0)
            steamcmd.sh +login anonymous +force_install_dir ./KF2Server +app_update 232130 validate -beta +exit
            ;;

        1)
            steamcmd.sh +login anonymous +force_install_dir ./KF2Server +app_update 232130 validate -beta $1 +exit
            ;;
    esac
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]
then
    exit 1
fi

case $1 in
    start)
        # we have to reload every time coz startup parameters might've changed
        sudo /bin/systemctl daemon-reload
        start_kf2
        ;;

    stop)
        stop_kf2
        ;;

    restart)
        sudo /bin/systemctl daemon-reload
        sudo /bin/systemctl restart kf2.service
        ;;

    status)
        sudo /bin/systemctl status kf2.service
        ;;

    update)
        if [ $# -eq 2 ]
        then
            update_kf2 $2
        else
            update_kf2
        fi
        ;;

    log)
        sudo /bin/journalctl --system --unit=kf2.service --follow
        ;;

    config)
        regen_conf
        ;;

    purge)
        purge_map $2
        ;;

    init)
        init_kf2
        ;;

    info)
        get_install
        ;;

    verify)
        if [ $# -eq 2 ]
        then
            check_integrity $2
        else
            check_integrity
        fi
        ;;

    help)
        print_help
        ;;

    *)
        exit 1

esac
