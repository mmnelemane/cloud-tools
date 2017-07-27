#!/bin/bash

RST=`tput sgr0`
R=`tput setaf 1`
G=`tput setaf 2`
B=`tput setaf 4`
M=`tput setaf 5`
C=`tput setaf 6`
reset=`tput sgr0`

MYDIR="$(dirname "$0")"
source $MYDIR/config

echo "${C}--------------------------------------------------------------------------"
echo "This script will setup Contrail Contrail Plane on this node"
echo "Make sure that you have setup repos on Admin node first"
echo "--------------------------------------------------------------------------${RST}"
read -rsn1 -p"Press any key to continue";echo

echo "--------------------------------------------------------------------------"
echo "-${M} Checking Kernel ${RST}"
echo "It will perform the following steps:"
echo "- Check Kernel"
check_kernel()
echo "- Add contrail repos"
echo "- Install packages to run Contrail Control Plane"
echo "- Install Contrail rpms"
install_packages()
echo "- Configure HAProxy"
haproxy_setup()
echo "- Configure Cassandra"
cassandra_setup()
echo "- Configure Zookeeper"
zookeeper_setup()
echo "- Configure RabbitMQ server"
rabbitmq_setup()
echo "- Configure Redis"
redis_setup()
echo "- Configure Opscenter"
opscenter_setup()
echo "- Configure Datastax agent"
datastax_agent_setup()
echo "- Configure Contrail Database"
supervisor_database_setup()
echo "- Configure Contrail Config"
supervisor_config_setup()
echo "- Configure Contrail Analytics"
supervisor_analytics_setup()
echo "- Configure Contrail Control"
supervisor_control_setup()
echo "- Configure Contrail WebUI"
supervisor_webui_setup()
echo "- Install Contrail tools"
provision_cp()

function check_kernel()
{
    KVER=`uname -a |awk '{print $3}'`
    echo "Installed kernel - $KVER"
    if [ "$KVER" == "4.4.59-92.17-default" ]; then
      echo "${G}Kernel version supported${RST}"
    else
      echo "${R}Kernel version not supported. Please upgrade/downgrade your kernel to 4.4.59-92.17-default"
      echo "Run 'zypper in kernel-default=4.4.59-92.17.3' and then reboot the machine ${RST}"
      exit 0
    fi
}

function install_packages ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Adding contrail repo ${RST}"
    zypper addrepo http://$ADMINIP:8091/suse-12.2/x86_64/repos/contrail/ contrail
    zypper ref
    echo "--------------------------------------------------------------------------"
    
    general_pkgs="python-devel haproxy zookeeper libzookeeper libzookeeper-devel python-zookeeper
                  cassandra cassandra-cpp-driver cassandra-tools libcassandra2 rabbitmq-server
                  redis redis-py yum ifmap-server cyrus-sasl-plain python-cassandra-driver
                  opscenter"
    
    contrail_pkgs="contrail-database contrail-database-common contrail-analytics contrail-config
                   contrail-control contrail-web-controller contrail-config-openstack contrail-dns
                   contrail-docs contrail-nodemgr python-contrail contrail-openstack-webui
                   contrail-setup contrail-utils contrail-lib"
    
    echo "--------------------------------------------------------------------------"
    echo "-${M} Install packages to run Contrail Control Plane ${RST}"
    for pkg in $general_pkgs; do
        zypper -n --no-gpg-checks in $pkg
    done
    
    echo "--------------------------------------------------------------------------"
    echo "-${M} Install contrail rpms ${RST}"
    for pkg in $contrail_pkgs; do
        zypper -n --no-gpg-checks in $pkg
    done
}

function haproxy_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure HAProxy ${RST}"
    
    cat << EOF > /etc/haproxy/haproxy.cfg
    
    global
      log /dev/log daemon
      maxconn 32768
      chroot /var/lib/haproxy
      user haproxy
      group haproxy
      daemon
      stats socket /var/lib/haproxy/stats user haproxy group haproxy mode 0640 level operator
      tune.bufsize 32768
      tune.ssl.default-dh-param 2048
      ssl-default-bind-ciphers ALL:!aNULL:!eNULL:!EXPORT:!DES:!3DES:!MD5:!PSK:!RC4:!ADH:!LOW@STRENGTH
    
    defaults
      log     global
      mode    http
      option  log-health-checks
      option  log-separate-errors
      option  dontlog-normal
      option  dontlognull
      option  httplog
      option  socket-stats
      retries 3
      option  redispatch
      maxconn 10000
      timeout connect     5s
      timeout client     50s
      timeout server    450s
    
    
    #---------------------------------------------------------------------
    # main frontend which proxys to the backends
    #---------------------------------------------------------------------
    frontend  main 
        bind *:5001
        #acl url_static       path_beg       -i /static /images /javascript /stylesheets
        #acl url_static       path_end       -i .jpg .gif .png .css .js
    
        #use_backend static          if url_static
        default_backend             app
    
    
    #---------------------------------------------------------------------
    # static backend for serving up images, stylesheets and such
    #---------------------------------------------------------------------
    backend static
        balance     roundrobin
        server      static 127.0.0.1:4331 check
    
    #---------------------------------------------------------------------
    # round robin balancing between the various backends
    #---------------------------------------------------------------------
    backend app
        balance     roundrobin
        server  app1 127.0.0.1:5001 check
        server  app2 127.0.0.1:5002 check
        server  app3 127.0.0.1:5003 check
        server  app4 127.0.0.1:5004 check
    
    #contrail-config-marker-start
    
    global  
            tune.maxrewrite 1024
    
    listen contrail-config-stats 
       bind :5937
       mode http
       stats enable
       stats uri /
       stats auth haproxy:557cfedc2e9ff031407e
    
    frontend  quantum-server 
        bind *:9696
        default_backend    quantum-server-backend
    
    frontend  contrail-api 
        bind *:8082
        default_backend    contrail-api-backend
        timeout client 3m
    
    frontend  contrail-discovery 
        bind *:5998
        default_backend    contrail-discovery-backend
    
    backend quantum-server-backend
        option nolinger
        balance     roundrobin
    
        server $CIP $CIP:9697 check inter 2000 rise 2 fall 3
    
    
    backend contrail-api-backend
        option nolinger
        timeout server 3m
        balance     roundrobin
    
        server $CIP $CIP:9100 check inter 2000 rise 2 fall 3
    
    backend contrail-discovery-backend
        option nolinger
        balance     roundrobin
        server $CIP $CIP:9110 check inter 2000 rise 2 fall 3
    
    #contrail-config-marker-end
    
    EOF
    
    echo 557cfedc2e9ff031407e > /etc/contrail/haproxy.token
    
    echo "- ${G}Starting HAProxy ${RST}"
    systemctl restart haproxy
    sleep 2
    systemctl status haproxy
}


function cassandra_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "- ${M}Configure Cassandra ${RST}"
    
    sed -i "s/cluster_name: 'Test Cluster'/cluster_name: 'Contrail'/g" /etc/cassandra/conf/cassandra.yaml
    sed -i "s/\"127.0.0.1\"/\"$CIP\"/g" /etc/cassandra/conf/cassandra.yaml
    sed -i "s/localhost/$CIP/g" /etc/cassandra/conf/cassandra.yaml
    sed -i "s/start_rpc: false/start_rpc: true/g" /etc/cassandra/conf/cassandra.yaml
    sed -i 's/JVM_OPTS="$JVM_OPTS -Xss180k"/JVM_OPTS="$JVM_OPTS -Xss512k"/g' /etc/cassandra/conf/cassandra-env.sh
    
    mkdir -p /var/lib/cassandra
    chown cassandra:cassandra /var/lib/cassandra
    
    echo "- ${G}Starting cassandra ${RST}"
    systemctl restart cassandra
    sleep 5
    echo "- ${G}Checking status${RST}"
    systemctl status cassandra
    sleep 2
    echo "- ${G}nodetool status${RST}"
    nodetool status
    sleep 2
    echo "- ${G}nodetool info${RST}"
    nodetool info
}

function zookeeper_setup()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure Zookeeper ${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /etc/zookeeper/zoo.cfg

    server.1=$CIP:2888:3888
    tickTime=2000
    initLimit=10
    syncLimit=5
    dataDir=/var/lib/zookeeper/data
    clientPort=2181
    maxSessionTimeout=120000
    autopurge.purgeInterval3

    EOF
    
    cat << EOF > /etc/zookeeper/java.env

    ZOO_LOG4J_PROP="INFO,ROLLINGFILE"
    ZOO_LOG_DIR="/var/log/zookeeper/"

    EOF
    
    cat << EOF > /etc/zookeeper/environment

    ZOO_LOG4J_PROP=INFO,CONSOLE,ROLLINGFILE

    EOF
    
    echo 1 > /var/lib/zookeeper/data/myid
    
    chown -R zookeeper:zookeeper /var/log/zookeeper
    echo "- ${G}Starting Zookeeper${RST}"
    
    cp ./extra/zkServer.sh /usr/bin/
    
    systemctl restart zookeeper
    sleep 2
    echo "- ${G}Checking status  ${RST}"
    systemctl status zookeeper
}

function rabbitmq_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure Rabbitmq-server ${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /etc/rabbitmq/rabbitmq.config
    [
       {rabbit, [ {tcp_listeners, [{"$CIP", 5672}]},
       {loopback_users, []},
       {log_levels,[{connection, info},{mirroring, info}]} ]
        }
    ].
    EOF
    
    HOSTNAME=$("hostname")
    
    cat << EOF > /etc/rabbitmq/rabbitmq-env.conf
    NODE_IP_ADDRESS=$CIP
    NODENAME=rabbit@$HOSTNAME-ctrl
    EOF
    
    cat << EOF >> /etc/hosts
    $CIP	$HOSTNAME	$HOSTNAME-ctrl
    EOF
    
    echo "- ${G}Starting Rabbitmq-server${RST}"
    systemctl restart rabbitmq-server
    sleep 2
    echo "- ${G} Checking status${RST}"
    systemctl status rabbitmq-server
    echo "- ${G}rabbitmqctl cluster_status${RST}"
    rabbitmqctl cluster_status
}

function redis_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure Redis ${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cp /etc/redis/default.conf.example /etc/redis/redis.conf
    sed -i "s/tcp-backlog 511/tcp-backlog 4096/g" /etc/redis/redis.conf
    sed -i "s/bind 127.0.0.1/#bind 127.0.0.1/g" /etc/redis/redis.conf
    
    sysctl -w net.core.somaxconn=4096 > /dev/null 2>&1
    sysctl -w vm.overcommit_memory=1 > /dev/null 2>&1
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    
    cat << EOF > /usr/lib/systemd/system/redis.service
    [Unit]
    Description=Redis In-Memory Data Store
    After=network.target
    
    [Service]
    ExecStart=/usr/sbin/redis-server /etc/redis/redis.conf
    ExecStop=/usr/bin/redis-cli shutdown
    Restart=always
    
    [Install]
    WantedBy=multi-user.target
    EOF
    
    systemctl daemon-reload
    sleep 2
    
    echo "- ${G}Starting Redis server${RST}"
    systemctl restart redis
    sleep 2
    echo "- ${G}Checking status${RST}"
    systemctl status redis
}

function opscenter_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure Opscenter ${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    if getent passwd contrail > /dev/null 2>&1; then
        echo "User contrail already exists"
    else
        echo "Adding user contrail"
        useradd contrail
    fi
    
    if getent group contrail > /dev/null 2>&1; then
        echo "Group contrail already exists"
    else
        echo "Adding group contrail"
        groupadd contrail
    fi
    
    USERID=$(id -u contrail)
    GROUPID=$(id -g contrail)
    
    chown -R contrail:contrail /var/log/opscenter/
 
    echo "- ${G}Starting Opscenter${RST}"
    PYTHONPATH=/usr/share/opscenter/lib/py-unpure/:/usr/share/opscenter/lib/py/ /usr/bin/python2.7 /usr/share/opscenter/bin/twistd -u $USERID -g $GROUPID --pidfile /var/run/opscenter/opscenterd.pid -oy /usr/share/opscenter/bin/start_opscenter.py
    sleep 2
    echo "- ${G}Checking status${RST}"
    ps -elf | grep opscenter | grep contrail
}

function datastax_agent_setup ()
{
    echo "--------------------------------------------------------------------------"
    echo "-${M} Configure Datastax agent ${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    echo "- ${G}Installing agent${RST}"
    rpm -ivh /usr/share/opscenter/agent/datastax-agent.rpm
    sleep 2
    
    echo "- ${G}Starting datastax agent${RST}"
    nohup java -Xmx128M -Djclouds.mpu.parts.magnitude=100000 -Djclouds.mpu.parts.size=16777216 -Dopscenter.ssl.trustStore=/var/lib/datastax-agent/ssl/agentKeyStore -Dopscenter.ssl.keyStore=/var/lib/datastax-agessl/agentKeyStore -Dopscenter.ssl.keyStorePassword=opscenter -Dagent-pidfile=/var/run/datastax-agent/datastax-agent.pid -Dlog4j.configuration=file:/etc/datastax-agent/log4j.properties -Djava.security.auth.login.config=/etc/datastax-agent/kerberos.config -jar /usr/share/datastax-agent/datastax-agent-5.2.4-standalone.jar /var/lib/datastax-agent/conf/address.yaml </dev/null &>/dev/null &
    
    sleep 1
    echo "- ${G}Starting datastax agent monitor${RST}"
    /usr/share/datastax-agent/bin/datastax_agent_monitor  </dev/null &>/dev/null &
}

function supervisor_database_setup ()
{
    echo "- ${G}Configure Contrail Database${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /usr/lib/systemd/system/supervisor-database.service
    [Unit]
    Description=Contrail database
    After=rc-local.service
    
    [Service]
    Type=forking
    ExecStart=/usr/bin/supervisord -c /etc/contrail/supervisord_database.conf
    
    [Install]
    WantedBy=multi-user.target
    EOF
    
    cat << EOF > /etc/contrail/supervisord_database.conf
    [unix_http_server]
    file=/var/run/supervisord_database.sock   ; (the path to the socket file)
    chmod=0700                 ; socket file mode (default 0700)
    
    [supervisord]
    logfile=/var/log/contrail/supervisord_contrail_database.log  ; (main log file;default $CWD/supervisord.log)
    logfile_maxbytes=10MB        ; (max main logfile bytes b4 rotation;default 50MB)
    logfile_backups=5           ; (num of main logfile rotation backups;default 10)
    loglevel=info                ; (log level;default info; others: debug,warn,trace)
    pidfile=/var/run/supervisord_contrail_database.pid  ; (supervisord pidfile;default supervisord.pid)
    nodaemon=false               ; (start in foreground if true;default false)
    minfds=1024                  ; (min. avail startup file descriptors;default 1024)
    minprocs=200                 ; (min. avail process descriptors;default 200)
    nocleanup=true              ; (dont clean up tempfiles at start;default false)
    
    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
    
    [supervisorctl]
    serverurl=unix:///var/run/supervisord_database.sock ; use a unix:// URL  for a unix socket
    
    autostart=true                ; start at supervisord start (default: true)
    stopsignal=KILL               ; signal used to kill process (default TERM)
    killasgroup=false             ; SIGKILL the UNIX process group (def false)
    
    [include]
    files = /etc/contrail/supervisord_database_files/*.ini
    EOF

    cat << EOF > /etc/contrail/supervisord_database_files/contrail-database-nodemgr.ini
    [eventlistener:contrail-database-nodemgr]
    command=/bin/bash -c "exec python /usr/bin/contrail-nodemgr --nodetype=contrail-database"
    environment_file= /etc/contrail/database_nodemgr_param
    events=PROCESS_COMMUNICATION,PROCESS_STATE,TICK_60
    events=PROCESS_COMMUNICATION,PROCESS_STATE,TICK_60
    buffer_size=10000                ; event buffer queue size (default 10)
    stdout_logfile=/var/log/contrail/contrail-database-nodemgr-stdout.log ; stdout log path, NONE for none; default AUTO
    stderr_logfile=/var/log/contrail/contrail-database-nodemgr-stderr.log ; stderr log path, NONE for none; default AUTO
    EOF
    
    cat << EOF > /etc/contrail/supervisord_database_files/kafka.ini
    [program:kafka]
    command=/usr/share/kafka/bin/kafka-server-start.sh /usr/share/kafka/config/server.properties
    autostart=true                ; start at supervisord start (default: true)
    killasgroup=false             ; SIGKILL the UNIX process group (def false)
    environment=LOG_DIR=/var/log/kafka
    EOF
    
    cat << EOF > /etc/contrail/supervisord_database_files/contrail-database.rules
    { "Rules": []}
    EOF
 
    cat << EOF > /etc/contrail/contrail-database-nodemgr.conf
    [DEFAULT]
    hostip=$CIP
    minimum_diskGB=10
    
    [DISCOVERY]
    server=$CIP
    port=5998
    EOF
    
    cat << EOF > /etc/contrail/vnc_api_lib.ini
    [global]
    ;WEB_SERVER = 127.0.0.1
    ;WEB_PORT = 9696  ; connection through quantum plugin
    
    WEB_SERVER = 127.0.0.1
    WEB_PORT = 8082 ; connection to api-server directly
    BASE_URL = /
    ;BASE_URL = /tenants/infra ; common-prefix for all URLs
    
    ; Authentication settings (optional)
    [auth]
    AUTHN_TYPE = keystone
    AUTHN_PROTOCOL = http
    AUTHN_SERVER=$AUTHIP
    AUTHN_PORT = 35357
    AUTHN_URL = /v2.0/tokens
    EOF
    
    mkdir -p /var/crashes
    echo "- ${G}Starting Contrail Database Node${RST}"
    systemctl daemon-reload
    systemctl restart supervisor-database
    service contrail-database start
    sleep 5
    echo "- ${G}Checking status${RST}"
    systemctl status supervisor-database
}

function supervisor_config_setup ()
{
    echo "- ${G}Configure Contrail Config${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /usr/lib/systemd/system/supervisor-config.service
    [Unit]
    Description=Contrail config
    After=rc-local.service
    
    [Service]
    Type=forking
    ExecStart=/usr/bin/supervisord -c /etc/contrail/supervisord_config.conf
    
    [Install]
    WantedBy=multi-user.target
    EOF
 
    cat << EOF > /etc/contrail/supervisord_config.conf
    [unix_http_server]
    file=/var/run/supervisord_config.sock   ; (the path to the socket file)
    chmod=0700                 ; socket file mode (default 0700)
    
    [supervisord]
    logfile=/var/log/contrail/supervisord-config.log ; (main log file;default /supervisord.log)
    logfile_maxbytes=50MB        ; (max main logfile bytes b4 rotation;default 50MB)
    logfile_backups=3            ; (num of main logfile rotation backups;default 10)
    loglevel=info                ; (log level;default info; others: debug,warn,trace)
    pidfile=/var/run/supervisord-config.pid   ; (supervisord pidfile;default supervisord.pid)
    nodaemon=false               ; (start in foreground if true;default false)
    minfds=1024                  ; (min. avail startup file descriptors;default 1024)
    minprocs=200                 ; (min. avail process descriptors;default 200)
    nocleanup=true              ; (dont clean up tempfiles at start;default false)
    childlogdir=/var/log/contrail ; (AUTO child log dir, default )
    
    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
    
    [supervisorctl]
    serverurl=unix:///var/run/supervisord-config.sock ; use a unix:// URL  for a unix socket
    buffer_size=10000                ; event buffer queue size (default 10)
    ;stdout_logfile=/var/log/contrail/contrail-support-service-nodemgr-stdout.log       ; stdout log path, NONE for none; default AUTO
    ;stderr_logfile=/var/log/contrail/contrail-support-service-nodemgr-stderr.log ; stderr log path, NONE for none; default AUTO
    
    [include]
    files = /etc/contrail/supervisord_config_files/*.ini
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-api.ini
    [program:contrail-api]
    command=/usr/bin/contrail-api --conf_file /etc/contrail/contrail-api.conf --conf_file /etc/contrail/contrail-keystone-auth.conf --conf_file /etc/contrail/contrail-database.conf --listen_port 910%(process_num)01d --worker_id %(process_num)s
    numprocs=1
    process_name=%(process_num)s
    redirect_stderr=true
    stdout_logfile= /var/log/contrail/contrail-api-%(process_num)s-stdout.log
    stderr_logfile=/dev/null
    priority=440
    autostart=true
    killasgroup=true
    stopsignal=KILL
    exitcodes=0
    EOF

    cat << EOF > /etc/contrail/supervisord_config_files/contrail-config-nodemgr.ini
    [eventlistener:contrail-config-nodemgr]
    command=/bin/bash -c "exec python /usr/bin/contrail-nodemgr --nodetype=contrail-config"
    events=PROCESS_COMMUNICATION,PROCESS_STATE,TICK_60
    ;[eventlistener:theeventlistenername]
    ;command=/bin/eventlistener    ; the program (relative uses PATH, can take args)
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    ;events=EVENT                  ; event notif. types to subscribe to (req'd)
    buffer_size=10000                ; event buffer queue size (default 10)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=-1                   ; the relative start priority (default -1)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    stdout_logfile=/var/log/contrail/contrail-config-nodemgr-stdout.log       ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    stderr_logfile=/var/log/contrail/contrail-config-nodemgr-stderr.log ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups        ; # of stderr logfile backups (default 10)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-config.rules
    { "Rules": [
        {"processname": "contrail-api", "process_state": "PROCESS_STATE_STOPPED", "action": "sudo service ifmap restart"},
        {"processname": "contrail-api", "process_state": "PROCESS_STATE_EXITED", "action": "sudo service ifmap restart"},
        {"processname": "contrail-api", "process_state": "PROCESS_STATE_FATAL", "action": "sudo service ifmap restart"}
         ]
    }
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-device-manager.ini
    [program:contrail-device-manager]
    command=/usr/bin/contrail-device-manager --conf_file /etc/contrail/contrail-device-manager.conf --conf_file /etc/contrail/contrail-keystone-auth.conf --conf_file /etc/contrail/contrail-database.conf
    priority=450
    autostart=true
    autorestart=true
    killasgroup=true
    stopsignal=TERM
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-device-manager-stdout.log
    stderr_logfile=/dev/null
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-discovery.ini
    [program:contrail-discovery]
    command=/usr/bin/contrail-discovery --conf_file /etc/contrail/contrail-discovery.conf --listen_port 911%(process_num)01d --worker_id %(process_num)s
    ;command=/bin/bash -c "source /opt/contrail/api-venv/bin/activate && exec python /opt/contrail/api-venv/lib/python2.7/site-packages/discovery/disc_server.py --conf_file /etc/contrail/contrail-discovery.conf --listen_port 911%(process_num)01d --worker_id %(process_num)s"
    numprocs=1
    process_name=%(process_num)s
    redirect_stderr=true
    stdout_logfile= /var/log/contrail/contrail-discovery-%(process_num)s-stdout.log
    stderr_logfile=/dev/null
    priority=430
    autostart=true
    killasgroup=true
    stopsignal=KILL
    exitcodes=0
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-schema.ini
    [program:contrail-schema]
    command=/usr/bin/contrail-schema --conf_file /etc/contrail/contrail-schema.conf --conf_file /etc/contrail/contrail-keystone-auth.conf --conf_file /etc/contrail/contrail-database.conf
    priority=450
    autostart=true
    autorestart=true
    killasgroup=true
    stopsignal=TERM
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-schema-stdout.log
    stderr_logfile=/dev/null
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/contrail-svc-monitor.ini
    [program:contrail-svc-monitor]
    command=/usr/bin/contrail-svc-monitor --conf_file /etc/contrail/contrail-svc-monitor.conf --conf_file /etc/contrail/contrail-keystone-auth.conf --conf_file /etc/contrail/contrail-database.conf
    priority=460
    autostart=true
    autorestart=true
    killasgroup=true
    stopsignal=TERM
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-svc-monitor-stdout.log
    stderr_logfile=/dev/null
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_config_files/ifmap.ini
    [program:ifmap]
    command=/usr/bin/ifmap-server
    priority=420
    autostart=true
    autorestart=true
    killasgroup=true
    stopasgroup=true
    stopsignal=TERM
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/ifmap-stdout.log
    stderr_logfile=/dev/null
    user=contrail
    EOF
    
    cat << EOF > /etc/ifmap-server/basicauthusers.properties
    api-server:api-server
    schema-transformer:schema-transformer
    svc-monitor:svc-monitor
    control-user:control-user-passwd
    dhcp:dhcp
    visual:visual
    sensor:sensor
    
    # compliance testsuite users
    mapclient:mapclient
    helper:mapclient
    
    # This is a read-only MAPC
    reader:reader
    
    $CIP:$CIP
    $CIP.dns:$CIP.dns
    EOF
    
    
    cat << EOF > /etc/contrail/contrail-api.conf
    [DEFAULTS]
    ifmap_server_ip=$CIP
    ifmap_server_port=8443
    ifmap_username=api-server
    ifmap_password=api-server
    cassandra_server_list=$CIP:9160
    listen_ip_addr=0.0.0.0
    listen_port=8082
    auth=keystone
    multi_tenancy=false
    log_file=/var/log/contrail/api.log
    log_local=1
    log_level=SYS_NOTICE
    disc_server_ip=$CIP
    disc_server_port=5998
    
    zk_server_ip=$CIP:2181
    rabbit_server=$CIP
    rabbit_port=5672
    
    ifmap_server_ip = $CIP
    redis_server = 127.0.0.1
    aaa_mode = rbac
    listen_ip_addr = $CIP
    rabbit_server = $CIP:5672
    auth = keystone
    listen_port = 8082
    
    [SECURITY]
    use_certs=false
    keyfile=/etc/contrail/ssl/private_keys/apiserver_key.pem
    certfile=/etc/contrail/ssl/certs/apiserver.pem
    ca_certs=/etc/contrail/ssl/certs/ca.pem
    
    [KEYSTONE]
    auth_host=$AUTHIP
    auth_protocol=http
    auth_port=35357
    admin_user=$AUTHUSER
    admin_password=$AUTHPASS
    admin_tenant_name=$ADMINTENANT
    insecure=false
    auth_plugin = password
    #memcache_servers=127.0.0.1:11211
    EOF
    
    cat << EOF > /etc/contrail/contrail-config-nodemgr.conf
    [DISCOVERY]
    server=$CIP
    port=5998
    EOF
    
    cat << EOF > /etc/contrail/contrail-device-manager.conf
    [DEFAULTS]
    rabbit_server=$CIP:5672
    api_server_ip=$CIP
    disc_server_ip=$CIP
    api_server_port=8082
    rabbit_port=5672
    zk_server_ip=$CIP:2181
    log_file=/var/log/contrail/contrail-device-manager.log
    cassandra_server_list=$CIP:9160
    disc_server_port=5998
    log_local=1
    log_level=SYS_NOTICE
    redis_server = 127.0.0.1
    EOF
    
    cat << EOF > /etc/contrail/contrail-discovery.conf
    [DEFAULTS]
    zk_server_ip=$CIP:2181
    zk_server_port=2181
    listen_ip_addr=0.0.0.0
    listen_port=5998
    log_local=True
    log_file=/var/log/contrail/contrail-discovery.log
    log_level=SYS_NOTICE
    cassandra_server_list = $CIP:9160
    
    ttl_min=300
    ttl_max=1800
    hc_interval=5
    hc_max_miss=3
    ttl_short=1
    
    [DNS-SERVER]
    policy=fixed
    EOF
    
    cat << EOF > /etc/contrail/contrail-schema.conf
    [DEFAULTS]
    ifmap_server_ip=$CIP
    ifmap_server_port=8443
    ifmap_username=schema-transformer
    ifmap_password=schema-transformer
    
    api_server_ip=$CIP
    api_server_port=8082
    
    rabbit_server = $CIP:5672
    
    zk_server_ip=$CIP:2181
    
    log_file=/var/log/contrail/schema.log
    
    cassandra_server_list=$CIP:9160
    
    disc_server_ip=$CIP
    disc_server_port=5998
    
    log_local=1
    
    log_level=SYS_NOTICE
    redis_server = 127.0.0.1
    
    rabbit_server=$CIP:5672
    rabbit_port=5672

    [SECURITY]
    use_certs=false
    keyfile=/etc/contrail/ssl/private_keys/schema_xfer_key.pem
    certfile=/etc/contrail/ssl/certs/schema_xfer.pem
    ca_certs=/etc/contrail/ssl/certs/ca.pem
    
    [KEYSTONE]
    auth_host=$AUTHIP
    auth_protocol=http
    auth_port=35357
    admin_user=$AUTHUSER
    admin_password=$AUTHPASS
    admin_tenant_name=$ADMINTENANT
    insecure=false
    memcache_servers=127.0.0.1:11211
    EOF
    
    cat << EOF > /etc/contrail/contrail-svc-monitor.conf
    [DEFAULTS]
    ifmap_server_ip=$CIP
    ifmap_server_port=8443
    ifmap_username=svc-monitor
    ifmap_password=svc-monitor
    api_server_ip=$CIP
    api_server_port=8082
    zk_server_ip=$CIP:2181
    log_file=/var/log/contrail/svc-monitor.log
    cassandra_server_list=$CIP:9160
    disc_server_ip=$CIP
    disc_server_port=5998
    region_name=RegionOne
    log_local=1
    log_level=SYS_NOTICE
    rabbit_server=$CIP:5672
    rabbit_port=5672
    
    redis_server = 127.0.0.1
    
    
    [SECURITY]
    use_certs=false
    keyfile=/etc/contrail/ssl/private_keys/svc_monitor_key.pem
    certfile=/etc/contrail/ssl/certs/svc_monitor.pem
    ca_certs=/etc/contrail/ssl/certs/ca.pem
    
    [SCHEDULER]
    analytics_server_ip=$CIP
    analytics_server_port=8081
    
    [KEYSTONE]
    auth_host=$AUTHIP
    admin_user=$AUTHUSER
    admin_password=$AUTHPASS
    admin_tenant_name=$ADMINTENANT
    EOF
    
    cat << EOF > /etc/contrail/contrail-keystone-auth.conf
    [KEYSTONE]
    auth_host=$AUTHIP
    auth_protocol=http
    auth_port=35357
    admin_user=$AUTHUSER
    admin_password=$AUTHPASS
    admin_tenant_name=$ADMINTENANT
    insecure=false
    memcache_servers=127.0.0.1:11211
    EOF
    
    
    echo "- ${G}Starting Contrail Config Node${RST}"
    systemctl daemon-reload
    systemctl restart supervisor-config
    sleep 5
    echo "- ${G}Checking status${RST}"
    systemctl status supervisor-config
}

function supervisor_analytics_setup ()
{
    echo "- ${G}Configure Contrail Analytics${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /usr/lib/systemd/system/supervisor-analytics.service
    [Unit]
    Description=Contrail analytics
    After=rc-local.service
    
    [Service]
    Type=forking
    ExecStart=/usr/bin/supervisord -c /etc/contrail/supervisord_analytics.conf
    
    [Install]
    WantedBy=multi-user.target
    EOF

    cat << EOF > /etc/contrail/supervisord_analytics.conf
    ; Sample supervisor config file.
    ;
    ; For more information on the config file, please see:
    ; http://supervisord.org/configuration.html
    ;
    ; Note: shell expansion ("~" or "$HOME") is not supported.  Environment
    ; variables can be expanded using this syntax: "%(ENV_HOME)s".
    
    [unix_http_server]
    file=/var/run/supervisord_analytics.sock    ; (the path to the socket file)
    chmod=0700                 ; socket file mode (default 0700)
    ;chown=nobody:nogroup       ; socket file uid:gid owner
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    ;[inet_http_server]         ; inet (TCP) server disabled by default
    ;port=127.0.0.1:9001        ; Port for analytics (ip_address:port specifier, *:port for all iface)
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    [supervisord]
    logfile=/var/log/contrail/supervisord-analytics.log   ; (main log file;default $CWD/supervisord.log)
    logfile_maxbytes=50MB        ; (max main logfile bytes b4 rotation;default 50MB)
    logfile_backups=3            ; (num of main logfile rotation backups;default 10)
    loglevel=info                ; (log level;default info; others: debug,warn,trace)
    pidfile=/var/run/supervisord-analytics.pid   ; (supervisord pidfile;default supervisord.pid)
    nodaemon=false               ; (start in foreground if true;default false)
    minfds=1024                  ; (min. avail startup file descriptors;default 1024)
    minprocs=200                 ; (min. avail process descriptors;default 200)
    ;umask=022                   ; (process file creation umask;default 022)
    ;user=chrism                 ; (default is current user, required if root)
    ;identifier=supervisor       ; (supervisord identifier, default is 'supervisor')
    ;directory=/tmp              ; (default is not to cd during start)
    nocleanup=true              ; (don't clean up tempfiles at start;default false)
    childlogdir=/var/log/contrail ; ('AUTO' child log dir, default $TEMP)
    ;environment=KEY=value       ; (key value pairs to add to environment)
    ;strip_ansi=false            ; (strip ansi escape codes in logs; def. false)
    
    ; the below section must remain in the config file for RPC
    ; (supervisorctl/web interface) to work, additional interfaces may be
    ; added by defining them in separate rpcinterface: sections
    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
    
    [supervisorctl]
    serverurl=unix:///var/run/supervisord_analytics.sock ; use a unix:// URL  for a unix socket
    ;serverurl=http://127.0.0.1:9001 ; use an http:// url to specify an inet socket
    ;username=chris              ; should be same as http_username if set
    ;password=123                ; should be same as http_password if set
    ;prompt=mysupervisor         ; cmd line prompt (default "supervisor")
    ;history_file=~/.sc_history  ; use readline history if available
    
    ; The below sample program section shows all possible program subsection values,
    ; create one or more 'real' program: sections to be able to control them under
    ; supervisor.
    
    ;[program:theprogramname]
    ;command=/bin/cat              ; the program (relative uses PATH, can take args)
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=999                  ; the relative start priority (default 999)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;user=chrism                   ; setuid to this UNIX account to run the program
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    ;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    ;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups=10     ; # of stderr logfile backups (default 10)
    ;stderr_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions (def no adds)
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    
    ; The below sample group section shows all possible group values,
    ; create one or more 'real' group: sections to create "heterogeneous"
    ; process groups.
    
    ;[group:thegroupname]
    ;programs=progname1,progname2  ; each refers to 'x' in [program:x] definitions
    ;priority=999                  ; the relative start priority (default 999)
    
    ; The [include] section can just contain the "files" setting.  This
    ; setting can list multiple files (separated by whitespace or
    ; newlines).  It can also contain wildcards.  The filenames are
    ; interpreted as relative to this file.  Included files *cannot*
    ; include files themselves.
    
    [include]
    files = /etc/contrail/supervisord_analytics_files/*.ini
    
    EOF
    
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-alarm-gen.ini
    [program:contrail-alarm-gen]
    command=/usr/bin/contrail-alarm-gen -c /etc/contrail/contrail-alarm-gen.conf -c /etc/contrail/contrail-keystone-auth.conf
    priority=440
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-alarm-gen-%(process_num)s-stdout.log
    stderr_logfile=/var/log/contrail/contrail-alarm-gen-%(process_num)s-stderr.log
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-analytics-api.ini
    [program:contrail-analytics-api]
    command=/usr/bin/contrail-analytics-api -c /etc/contrail/contrail-analytics-api.conf
    priority=440
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-analytics-api-stdout.log
    stderr_logfile=/var/log/contrail/contrail-analytics-api-stderr.log
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-analytics-nodemgr.ini
    [eventlistener:contrail-analytics-nodemgr]
    command=/bin/bash -c "exec /usr/bin/contrail-nodemgr"
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    events=PROCESS_COMMUNICATION,PROCESS_STATE,TICK_60
    buffer_size=10000                ; event buffer queue size (default 10)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=-1                   ; the relative start priority (default -1)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    stdout_logfile=/var/log/contrail/contrail-analytics-nodemgr-stdout.log        ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    stderr_logfile=/var/log/contrail/contrail-analytics-nodemgr-stderr.log ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups        ; # of stderr logfile backups (default 10)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-analytics.rules
    { "Rules": [
            {"processname": "contrail-query-engine", "process_state": "PROCESS_STATE_FATAL", "action": "service contrail-analytics-api stop"}
        ]
    }
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-collector.ini
    [program:contrail-collector]
    command=/usr/bin/contrail-collector  --conf_file /etc/contrail/contrail-collector.conf
    priority=420
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-collector-stdout.log
    stderr_logfile=/dev/null
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-query-engine.ini
    [program:contrail-query-engine]
    command=/usr/bin/contrail-query-engine --conf_file /etc/contrail/contrail-query-engine.conf
    priority=430
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-query-engine-stdout.log
    stderr_logfile=/dev/null
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-snmp-collector.ini
    [program:contrail-snmp-collector]
    command=/usr/bin/contrail-snmp-collector --conf_file /etc/contrail/contrail-snmp-collector.conf
    priority=340
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-snmp-collector-stdout.log
    stderr_logfile=/var/log/contrail/contrail-snmp-collector-stderr.log
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_analytics_files/contrail-topology.ini
    [program:contrail-topology]
    command=/usr/bin/contrail-topology --conf_file /etc/contrail/contrail-topology.conf
    priority=340
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-topology-stdout.log
    stderr_logfile=/var/log/contrail/contrail-topology-stderr.log
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/contrail-alarm-gen.conf
    [DEFAULTS]
    host_ip = $CIP
    #collectors = 127.0.0.1:8086
    #http_server_port = 5995
    log_local = 1
    log_level = SYS_NOTICE
    #log_category =
    log_file = /var/log/contrail/contrail-alarm-gen.log
    kafka_broker_list = $CIP:9092
    partitions=30
    zk_list = $CIP:2181
    rabbitmq_server_list = $CIP:5672
    rabbitmq_port = 5672
    
    
    [DISCOVERY]
    disc_server_ip = 127.0.0.1
    disc_server_port = 5998
    
    [REDIS]
    redis_server_port=6379
    EOF
    
    cat << EOF > /etc/contrail/contrail-analytics-api.conf
    [DEFAULTS]
    host_ip = $CIP
    cassandra_server_list=$CIP:9042
    http_server_port = 8090
    rest_api_port = 8081
    rest_api_ip = 0.0.0.0
    log_local = 1
    log_level = SYS_NOTICE
    log_category =
    log_file = /var/log/contrail/contrail-analytics-api.log
    partitions=30
    api_server = $CIP:8082
    aaa_mode = no-auth
    
    # Time-to-live in hours of the data stored by collector into cassandra
    analytics_data_ttl=48
    analytics_config_audit_ttl=168
    analytics_statistics_ttl=24
    analytics_flow_ttl=2
    
    [DISCOVERY]
    disc_server_ip = $CIP
    disc_server_port = 5998
    
    [REDIS]
    redis_server_port = 6379
    redis_query_port = 6379
    
    
    [KEYSTONE]
    auth_protocol = http
    admin_tenant_name = $ADMINTENANT
    auth_host = $AUTHIP
    insecure = false
    admin_user = $AUTHUSER
    admin_password = $AUTHPASS
    auth_port = 35357
    EOF
    
    cat << EOF > /etc/contrail/contrail-analytics-nodemgr.conf
    [DISCOVERY]
    server=$CIP
    port=5998
    EOF
    
    cat << EOF > /etc/contrail/contrail-collector.conf
    [DEFAULT]
    # Everything in this section is optional
    
    # Time-to-live in hours of the data stored by collector into cassandra
    analytics_data_ttl=48
    analytics_config_audit_ttl=168
    analytics_statistics_ttl=24
    analytics_flow_ttl=2
    
    kafka_broker_list=$CIP:9092
    partitions=30
    
    # IP address and port to be used to connect to cassandra.
    # Multiple IP:port strings separated by space can be provided
    cassandra_server_list=$CIP:9042
    
    # IP address of analytics node. Resolved IP of 'hostname'
    hostip=$CIP
    
    # Hostname of analytics node. If this is not configured value from ostname# will be taken
    # hostname=
    
    # Http server port for inspecting collector state (useful for debugging)
    http_server_port=8089
    
    # Category for logging. Default value is '*'
    # log_category=
    
    # Local log file name
    log_file=/var/log/contrail/collector.log
    
    # Maximum log file rollover index
    # log_files_count=10
    
    # Maximum log file size
    # log_file_size=1048576 # 1MB
    
    # Log severity levels. Possible values are SYS_EMERG, SYS_ALERT, SYS_CRIT,
    # SYS_ERR, SYS_WARN, SYS_NOTICE, SYS_INFO and SYS_DEBUG. Default is SYS_DEBUG
    log_level=SYS_NOTICE
    # Enable/Disable local file logging. Possible values are 0 (disable) and
    # 1 (enable)
    log_local=1
    
    # TCP and UDP ports to listen on for receiving syslog messages. -1 to disable.
    syslog_port=-1
    
    # UDP port to listen on for receiving sFlow messages. -1 to disable.
    # sflow_port=6343
    
    [COLLECTOR]
    # Everything in this section is optional
    
    # Port to listen on for receiving Sandesh messages
    port=8086
    
    # IP address to bind to for listening
    # server=0.0.0.0
    
    # UDP port to listen on for receiving Google Protocol Buffer messages
    # protobuf_port=3333
    
    [DISCOVERY]
    # Port to connect to for communicating with discovery server
    # port=5998
    
    # IP address of discovery server
    server=$CIP
    
    [REDIS]
    # Port to connect to for communicating with redis-server
    port=6379
    
    
    # IP address of redis-server
    server=127.0.0.1
    EOF
    
    cat << EOF > /etc/contrail/contrail-query-engine.conf
    [DEFAULT]
    # analytics_data_ttl=48
      cassandra_server_list=$CIP:9042
      hostip=$CIP # Resolved IP of crowbar
    # log_category=
    # log_disable=0
      log_file=/var/log/contrail/contrail-query-engine.log
    # log_files_count=10
    # log_file_size=1048576 # 1MB
      log_level=SYS_NOTICE
      log_local=1
    # test_mode=0
    
    [DISCOVERY]
      port=5998
      server=$CIP
    
    [REDIS]
      port=6379
      server=127.0.0.1
    EOF
    
    
    cat << EOF > /etc/contrail/contrail-snmp-collector.conf
    [DEFAULTS]
    log_local = 1
    log_level = SYS_NOTICE
    #log_category =
    log_file = /var/log/contrail/contrail-snmp-collector.log
    scan_frequency = 600
    fast_scan_frequency = 60
    http_server_port = 5920
    zookeeper=$CIP:2181
    
    [DISCOVERY]
    disc_server_ip=$CIP
    disc_server_port=5998
    
    [KEYSTONE]
    auth_host=$AUTHIP
    auth_protocol=http
    auth_port=35357
    admin_user=$AUTHUSER
    admin_password=$AUTHPASS
    #admin_token=crowbar
    admin_tenant_name=$ADMINTENANT
    insecure=false
    memcache_servers=127.0.0.1:11211
    EOF
    
    cat << EOF > /etc/contrail/contrail-topology.conf
    [DEFAULTS]
    log_local = 1
    log_level = SYS_NOTICE
    #log_category = ''
    log_file = /var/log/contrail/contrail-topology.log
    #use_syslog =
    #syslog_facility =
    scan_frequency = 60
    #http_server_port = 5921
    zookeeper=$CIP:2181
    
    [DISCOVERY]
    disc_server_ip = $CIP
    disc_server_port = 5998
    EOF
    
    cp /usr/bin/contrail-collector /usr/bin/contrail-collector.backup
    cp ./extra/contrail-collector /usr/bin/
    
    echo "Starting Contrail Analytics Node"
    systemctl daemon-reload
    systemctl restart supervisor-analytics
    sleep 5
    echo "Checking status"
    systemctl status supervisor-analytics
}

function supervisor_control_setup ()
{
    echo "- ${G}Configure Contrail Control${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /usr/lib/systemd/system/supervisor-control.service
    [Unit]
    Description=Contrail cotrol
    After=rc-local.service
    
    [Service]
    Type=forking
    ExecStart=/usr/bin/supervisord -c /etc/contrail/supervisord_control.conf
    
    [Install]
    WantedBy=multi-user.target
    EOF
    
    cat << EOF > /etc/contrail/supervisord_control.conf
    ; Sample supervisor config file.
    ;
    ; For more information on the config file, please see:
    ; http://supervisord.org/configuration.html
    ;
    ; Note: shell expansion ("~" or "$HOME") is not supported.  Environment
    ; variables can be expanded using this syntax: "%(ENV_HOME)s".
    
    [unix_http_server]
    file=/var/run/supervisord_control.sock   ; (the path to the socket file)
    chmod=0700                 ; socket file mode (default 0700)
    ;chown=nobody:nogroup       ; socket file uid:gid owner
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    ;[inet_http_server]         ; inet (TCP) server disabled by default
    ;port=127.0.0.1:9001        ; Port for analytics (ip_address:port specifier, *:port for all iface)
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    [supervisord]
    logfile=/var/log/contrail/supervisord-control.log ; (main log file;default $CWD/supervisord.log)
    logfile_maxbytes=50MB        ; (max main logfile bytes b4 rotation;default 50MB)
    logfile_backups=3            ; (num of main logfile rotation backups;default 10)
    loglevel=info                ; (log level;default info; others: debug,warn,trace)
    pidfile=/var/run/supervisord_control.pid ; (supervisord pidfile;default supervisord.pid)
    nodaemon=false               ; (start in foreground if true;default false)
    minfds=1024                  ; (min. avail startup file descriptors;default 1024)
    minprocs=200                 ; (min. avail process descriptors;default 200)
    ;umask=022                   ; (process file creation umask;default 022)
    ;user=chrism                 ; (default is current user, required if root)
    ;identifier=supervisor       ; (supervisord identifier, default is 'supervisor')
    ;directory=/tmp              ; (default is not to cd during start)
    nocleanup=true              ; (don't clean up tempfiles at start;default false)
    childlogdir=/var/log/contrail ; ('AUTO' child log dir, default $TEMP)
    ;environment=KEY=value       ; (key value pairs to add to environment)
    ;strip_ansi=false            ; (strip ansi escape codes in logs; def. false)
    
    ; the below section must remain in the config file for RPC
    ; (supervisorctl/web interface) to work, additional interfaces may be
    ; added by defining them in separate rpcinterface: sections
    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
    
    [supervisorctl]
    serverurl=unix:///var/run/supervisord_control.sock ; use a unix:// URL  for a unix socket
    ;serverurl=http://127.0.0.1:9001 ; use an http:// url to specify an inet socket
    ;username=chris              ; should be same as http_username if set
    ;password=123                ; should be same as http_password if set
    ;prompt=mysupervisor         ; cmd line prompt (default "supervisor")
    ;history_file=~/.sc_history  ; use readline history if available
    
    ; The below sample program section shows all possible program subsection values,
    ; create one or more 'real' program: sections to be able to control them under
    ; supervisor.
    
    ;[program:theprogramname]
    ;command=/bin/cat              ; the program (relative uses PATH, can take args)
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=999                  ; the relative start priority (default 999)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;user=chrism                   ; setuid to this UNIX account to run the program
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    ;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    ;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups=10     ; # of stderr logfile backups (default 10)
    ;stderr_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions (def no adds)
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    
    ; The below sample group section shows all possible group values,
    ; create one or more 'real' group: sections to create "heterogeneous"
    ; process groups.
    
    ;[group:thegroupname]
    ;programs=progname1,progname2  ; each refers to 'x' in [program:x] definitions
    ;priority=999                  ; the relative start priority (default 999)
    
    ; The [include] section can just contain the "files" setting.  This
    ; setting can list multiple files (separated by whitespace or
    ; newlines).  It can also contain wildcards.  The filenames are
    ; interpreted as relative to this file.  Included files *cannot*
    ; include files themselves.
    
    [include]
    files = /etc/contrail/supervisord_control_files/*.ini
    EOF
    
    cat << EOF > /etc/contrail/supervisord_control_files/contrail-control.ini
    [program:contrail-control]
    command=/usr/bin/authbind /usr/bin/contrail-control
    priority=520
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-control-stdout.log
    stderr_logfile=/dev/null
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_control_files/contrail-control.rules
    { "Rules": [
         ]
    }
    EOF
    
    cat << EOF > /etc/contrail/supervisord_control_files/contrail-dns.ini
    [program:contrail-dns]
    command=/usr/bin/contrail-dns
    priority=520
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-dns-stdout.log
    stderr_logfile=/dev/null
    startsecs=10
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    cat << EOF > /etc/contrail/supervisord_control_files/contrail-named.ini

    [program:contrail-named]
    command=/usr/bin/authbind /usr/bin/contrail-named -f -c /etc/contrail/dns/contrail-named.conf
    user=contrail
    priority=520
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    startsecs=5
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-named-stdout.log
    stderr_logfile=/dev/null
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    user=contrail
    EOF
    
    
    cat << EOF > /etc/contrail/supervisord_control_files/contrail-nodemgr-control.ini
    ; The below sample eventlistener section shows all possible
    ; eventlistener subsection values, create one or more 'real'
    ; eventlistener: sections to be able to handle event notifications
    ; sent by supervisor.
    
    [eventlistener:contrail-control-nodemgr]
    command=/bin/bash -c "exec python /usr/bin/contrail-nodemgr --nodetype=contrail-control"
    events=PROCESS_COMMUNICATION,PROCESS_STATE,TICK_60
    buffer_size=10000                ; event buffer queue size (default 10)
    stdout_logfile=/var/log/contrail/contrail-control-nodemgr-stdout.log ; stdout log path, NONE for none; default AUTO
    stderr_logfile=/var/log/contrail/contrail-control-nodemgr-stderr.log ; stderr log path, NONE for none; default AUTO
    EOF
    
    
    cat << EOF > /etc/contrail/contrail-control.conf
    #
    # Copyright (c) 2014 Juniper Networks, Inc. All rights reserved.
    #
    # Control-node configuration options
    #
    
    [DEFAULT]
    # bgp_config_file=bgp_config.xml
    # bgp_port=179
    # collectors= # Provided by discovery server
      hostip=$CIP # Resolved IP of crowbar
    #  hostip=ctrl1 # Resolved IP of crowbar
    # http_server_port=8083
    # log_category=
    # log_disable=0
      log_file=/var/log/contrail/contrail-control.log
    # log_files_count=10
    # log_file_size=10485760 # 10MB
      log_level=SYS_NOTICE
      log_local=1
    # test_mode=0
    # xmpp_server_port=5269
    
    [DISCOVERY]
    # port=5998
      server=$CIP # discovery-server IP address
    
    [IFMAP]
      certs_store=
      password=$CIP
      #server_url=https://vip:8443 # Provided by discovery server, e.g. https://127.0.0.1:8443
      user=$CIP
    EOF
    
    cat << EOF > /etc/contrail/contrail-dns.conf
    [DEFAULT]
    # collectors= # Provided by discovery server
    # dns_config_file=dns_config.xml
     hostip=$CIP # Resolved IP of crowbar
    # dns_server_port=53
    # log_category=
    # log_disable=0
      log_file=/var/log/contrail/dns.log
    # log_files_count=10
    # log_file_size=1048576 # 1MB
      log_level=SYS_NOTICE
      log_local=1
    # test_mode=0
    
    [DISCOVERY]
    # port=5998
    server=$CIP # discovery-server IP address
    
    [IFMAP]
      certs_store=
      password=$CIP.dns
      #server_url=https://vip:8443 # Provided by discovery server, e.g. https://127.0.0.1:8443
      user=$CIP.dns
    
    EOF
    
    cat << EOF > /etc/contrail/dns/contrail-named-base.conf
    options {
        directory "/etc/contrail/dns";
        managed-keys-directory "/etc/contrail/dns";
        empty-zones-enable no;
        pid-file "/etc/contrail/dns/contrail-named.pid";
        session-keyfile "/etc/contrail/dns/session.key";
        listen-on port 53 { any; };
        allow-query { any; };
        allow-recursion { any; };
        allow-query-cache { any; };
        max-cache-size 32M;
    };
    
    key "rndc-key" {
       algorithm hmac-md5;
       secret "xvysmOR8lnUQRBcunkC6vg==";
    };
    
    controls {
        inet 127.0.0.1 port 8094
        allow { 127.0.0.1; }  keys { "rndc-key"; };
    };
    
    logging {
        channel debug_log {
            file "/var/log/contrail/contrail-named.log" versions 5 size 5m;
            severity debug;
            print-time yes;
            print-severity yes;
            print-category yes;
        };
        category default {
            debug_log;
        };
        category queries {
            debug_log;
        };
    };
    EOF
    
    cat << EOF > /etc/contrail/contrail-control-nodemgr.conf
    [DISCOVERY]
    server=$CIP
    port=5998
    EOF
    
    mkdir -p /var/crashes
    echo "Starting Contrail Control Node"
    systemctl daemon-reload
    systemctl restart supervisor-control
    service contrail-database start
    sleep 5
    echo "Checking status"
    systemctl status supervisor-control
}

function supervisor_webui_setup ()
{
    echo "- ${G}Configure Contrail WebUI${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config
    
    cat << EOF > /usr/lib/systemd/system/supervisor-webui.service
    [Unit]
    Description=Contrail webui
    After=rc-local.service
    
    [Service]
    Type=forking
    ExecStart=/usr/bin/supervisord -c /etc/contrail/supervisord_webui.conf
    
    [Install]
    WantedBy=multi-user.target
    EOF
    
    
    
    cat << EOF > /etc/contrail/supervisord_webui.conf
    ; Sample supervisor config file.
    ;
    ; For more information on the config file, please see:
    ; http://supervisord.org/configuration.html
    ;
    ; Note: shell expansion ("~" or "$HOME") is not supported.  Environment
    ; variables can be expanded using this syntax: "%(ENV_HOME)s".
    
    [unix_http_server]
    file=/var/run/supervisord_webui.sock   ; (the path to the socket file)
    chmod=0700                 ; socket file mode (default 0700)
    ;chown=nobody:nogroup       ; socket file uid:gid owner
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    ;[inet_http_server]         ; inet (TCP) server disabled by default
    ;port=localhost:9008        ; Port for analytics (ip_address:port specifier, *:port for all iface)
    ;username=user              ; (default is no username (open server))
    ;password=123               ; (default is no password (open server))
    
    [supervisord]
    logfile=/var/log/contrail/supervisord-webui.log ; (main log file;default $CWD/supervisord.log)
    logfile_maxbytes=50MB        ; (max main logfile bytes b4 rotation;default 50MB)
    logfile_backups=3            ; (num of main logfile rotation backups;default 10)
    loglevel=info                ; (log level;default info; others: debug,warn,trace)
    pidfile=/var/run/supervisord_webui.pid ; (supervisord pidfile;default supervisord.pid)
    nodaemon=false               ; (start in foreground if true;default false)
    minfds=10240                 ; (min. avail startup file descriptors;default 1024)
    minprocs=200                 ; (min. avail process descriptors;default 200)
    ;umask=022                   ; (process file creation umask;default 022)
    ;user=chrism                 ; (default is current user, required if root)
    ;identifier=supervisor       ; (supervisord identifier, default is 'supervisor')
    ;directory=/tmp              ; (default is not to cd during start)
    ;nocleanup=true              ; (don't clean up tempfiles at start;default false)
    childlogdir=/var/log/contrail ; ('AUTO' child log dir, default $TEMP)
    ;environment=KEY=value       ; (key value pairs to add to environment)
    ;strip_ansi=false            ; (strip ansi escape codes in logs; def. false)
    
    ; the below section must remain in the config file for RPC
    ; (supervisorctl/web interface) to work, additional interfaces may be
    ; added by defining them in separate rpcinterface: sections
    [rpcinterface:supervisor]
    supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
    
    [supervisorctl]
    serverurl=unix:///var/run/supervisord_webui.sock ; use a unix:// URL  for a unix socket
    ;serverurl=http://127.0.0.1:9001 ; use an http:// url to specify an inet socket
    ;username=chris              ; should be same as http_username if set
    ;password=123                ; should be same as http_password if set
    ;prompt=mysupervisor         ; cmd line prompt (default "supervisor")
    ;history_file=~/.sc_history  ; use readline history if available
    
    ; The below sample program section shows all possible program subsection values,
    ; create one or more 'real' program: sections to be able to control them under
    ; supervisor.
    
    ;[program:theprogramname]
    ;command=/bin/cat              ; the program (relative uses PATH, can take args)
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=999                  ; the relative start priority (default 999)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;user=chrism                   ; setuid to this UNIX account to run the program
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    ;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    ;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups=10     ; # of stderr logfile backups (default 10)
    ;stderr_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions (def no adds)
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    
    ; The below sample eventlistener section shows all possible
    ; eventlistener subsection values, create one or more 'real'
    ; eventlistener: sections to be able to handle event notifications
    ; sent by supervisor.
    
    ;[eventlistener:theeventlistenername]
    ;command=/bin/eventlistener    ; the program (relative uses PATH, can take args)
    ;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
    ;numprocs=1                    ; number of processes copies to start (def 1)
    ;events=EVENT                  ; event notif. types to subscribe to (req'd)
    buffer_size=10000                ; event buffer queue size (default 10)
    ;directory=/tmp                ; directory to cwd to before exec (def no cwd)
    ;umask=022                     ; umask for process (default None)
    ;priority=-1                   ; the relative start priority (default -1)
    ;autostart=true                ; start at supervisord start (default: true)
    ;autorestart=unexpected        ; whether/when to restart (default: unexpected)
    ;startsecs=1                   ; number of secs prog must stay running (def. 1)
    ;startretries=3                ; max # of serial start failures (default 3)
    ;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
    ;stopsignal=QUIT               ; signal used to kill process (default TERM)
    ;stopwaitsecs=10               ; max num secs to wait b4 SIGKILL (default 10)
    ;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
    ;killasgroup=false             ; SIGKILL the UNIX process group (def false)
    ;user=chrism                   ; setuid to this UNIX account to run the program
    ;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
    ;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
    ;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
    ;stdout_events_enabled=false   ; emit events on stdout writes (default false)
    ;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
    ;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
    ;stderr_logfile_backups        ; # of stderr logfile backups (default 10)
    ;stderr_events_enabled=false   ; emit events on stderr writes (default false)
    ;environment=A=1,B=2           ; process environment additions
    ;serverurl=AUTO                ; override serverurl computation (childutils)
    
    ; The below sample group section shows all possible group values,
    ; create one or more 'real' group: sections to create "heterogeneous"
    ; process groups.
    
    ;[group:contrail-webui]
    ;programs=contrail-webui,contrail-webui-middleware; each refers to 'x' in [program:x] definitions
    ;priority=999                  ; the relative start priority (default 999)
    
    ; The [include] section can just contain the "files" setting.  This
    ; setting can list multiple files (separated by whitespace or
    ; newlines).  It can also contain wildcards.  The filenames are
    ; interpreted as relative to this file.  Included files *cannot*
    ; include files themselves.
    
    [include]
    files = /etc/contrail/supervisord_webui_files/*.ini
    EOF
    
    
    
    cat << EOF > /etc/contrail/supervisord_webui_files/contrail-webui.ini
    [program:contrail-webui]
    directory= /usr/src/contrail/contrail-web-core
    command= bash -c "node webServerStart.js"
    priority=420
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-webui-stdout.log
    stderr_logfile=/dev/null
    startretries=10
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    EOF
    
    cat << EOF > /etc/contrail/supervisord_webui_files/contrail-webui-middleware.ini
    [program:contrail-webui-middleware]
    directory= /usr/src/contrail/contrail-web-core
    command= bash -c "node jobServerStart.js"
    priority=420
    autostart=true
    killasgroup=true
    stopsignal=KILL
    stdout_capture_maxbytes=1MB
    redirect_stderr=true
    stdout_logfile=/var/log/contrail/contrail-webui-middleware-stdout.log
    stderr_logfile=/dev/null
    startretries=10
    startsecs=5
    exitcodes=0                   ; 'expected' exit codes for process (default 0,2)
    EOF
    
    
    
    cat << EOF > /etc/contrail/contrail-webui-userauth.js
    /****************************************************************************
     * Specify the authentication parameters for admin user
     ****************************************************************************/
    var auth = {};
    auth.admin_user = '$AUTHUSER';
    auth.admin_password = '$AUTHPASS';
    auth.admin_tenant_name = '$ADMINTENANT';
    
    module.exports = auth;
    EOF
    
    
    echo 'Configure config.global.js'
    sed -i "s/config.networkManager.ip =.*/config.networkManager.ip = '$AUTHIP';/g" /etc/contrail/config.global.js
    sed -i "s/config.imageManager.ip = .*/config.imageManager.ip = '$AUTHIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.computeManager.ip = .*/config.computeManager.ip = '$AUTHIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.identityManager.ip = .*/config.identityManager.ip = '$AUTHIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.storageManager.ip = .*/config.storageManager.ip = '$AUTHIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.cnfg.server_ip = .*/config.cnfg.server_ip = '$CIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.analytics.server_ip = .*/config.analytics.server_ip = '$CIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.discoveryService.server_ip = .*/discoveryService.server_ip = '$CIP'/g" /etc/contrail/config.global.js
    sed -i "s/config.cassandra.server_ips = .*/config.cassandra.server_ips = ['$CIP']/g" /etc/contrail/config.global.js
 
    cp ./extra/contrail.unified.css  /usr/src/contrail/contrail-web-core/webroot/dist/common/ui/css/
    cp ./extra/contrail.unified.css /usr/src/contrail/contrail-web-core/webroot/common/ui/css/
    cp ./extra/contrail.thirdparty.unified.css /usr/src/contrail/contrail-web-core/webroot/dist/common/ui/css/
    cp ./extra/contrail.thirdparty.unified.css /usr/src/contrail/contrail-web-core/webroot/common/ui/css/
    
    cd /usr/lib64/node_modules/
    npm install bindings
    cd /root/contrail/
    
    echo "Starting Contrail WebUI Node"
    systemctl daemon-reload
    systemctl restart supervisor-webui
    sleep 5
    echo "Checking status"
    systemctl status supervisor-webui
}

function provision_cp ()
{
    echo "- ${G}Provision contrail${RST}"
    MYDIR="$(dirname "$0")"
    source $MYDIR/config

    config_params="  --api_server_ip $CIP --admin_user $AUTHUSER --admin_password $AUTHPASS"
    config_params << " --admin_tenant_name $ADMINTENANT --oper add --host_name  $HOSTNAME --host_ip $CIP"
    
    python /opt/contrail/utils/provision_config_node.py $config_params
    
    python /opt/contrail/utils/provision_database_node.py $config_params
    
    python /opt/contrail/utils/provision_analytics_node.py $config_params
    
    python /opt/contrail/utils/provision_control.py $config_params --router_asn 64512
    
    python /opt/contrail/utils/provision_encap.py --api_server_ip $CIP --admin_user $AUTHUSER --admin_password $AUTHPASS --oper add --encap_priority MPLSoUDP,MPLSoGRE,VXLAN
    
    python /opt/contrail/utils/provision_linklocal.py --api_server_ip $CIP --admin_user $AUTHUSER --admin_password $AUTHPASS --admin_tenant_name $ADMINTENANT --oper add --ipfabric_service_ip $AUTHIP --ipfabric_service_port 8775 --linklocal_service_name metadata --linklocal_service_ip 169.254.169.254 --linklocal_service_port 80
    
}
