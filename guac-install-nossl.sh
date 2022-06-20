#!/bin/bash
# Respectully repurposed from ricmmartins "Apache Guacamole Azure" repo and guide.
# https://github.com/ricmmartins/apache-guacamole-azure/blob/main/guac-install.sh
#
# Modified to add nginx installation and configuration along with SSL settings

# Version numbers of Guacamole and MySQL Connector/J to download
GUACVERSION="0.9.14"

# Update apt so we can search apt-cache for newest tomcat version supported
apt update

# Get MySQL root password and Guacamole User password
guacdbuserpassword="mysqlpassword"
guacmysqlhostname="mysqldb.mysql.database.azure.com"
guacmysqlport="3306"
guacmysqldatabase="mysqldb"
guacmysqlusername="mysqladmin@mysqldb"
domainName="myguacamolelab.com"
email="admin@myguacamolelab.com"

# Ubuntu and Debian have different package names for libjpeg
# Ubuntu and Debian versions have differnet package names for libpng-dev
source /etc/os-release
if [[ "${NAME}" == "Ubuntu" ]]
then
    JPEGTURBO="libjpeg-turbo8-dev"
    if [[ "${VERSION_ID}" == "16.04" ]]
    then
        LIBPNG="libpng12-dev"
    else
        LIBPNG="libpng-dev"
    fi
elif [[ "${NAME}" == *"Debian"* ]]
then
    JPEGTURBO="libjpeg62-turbo-dev"
    if [[ "${PRETTY_NAME}" == *"stretch"* ]]
    then
        LIBPNG="libpng-dev"
    else
        LIBPNG="libpng12-dev"
    fi
else
    echo "Unsupported Distro - Ubuntu or Debian Only"
    exit
fi

# Tomcat 8.0.x is End of Life, however Tomcat 7.x is not...
# If Tomcat 8.5.x or newer is available install it, otherwise install Tomcat 7
if [[ $(apt-cache show tomcat8 | egrep "Version: 8.[5-9]" | wc -l) -gt 0 ]]
then
    TOMCAT="tomcat8"
else
    TOMCAT="tomcat7"
fi

# Uncomment to manually force a tomcat version
#TOMCAT=""

# Install features
apt -y install build-essential libcairo2-dev ${JPEGTURBO} ${LIBPNG} libossp-uuid-dev libavcodec-dev libavutil-dev \
libswscale-dev libfreerdp-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
libvorbis-dev libwebp-dev mysql-client mysql-common mysql-utilities libmysql-java ${TOMCAT} freerdp-x11 \
ghostscript wget dpkg-dev

# If apt fails to run completely the rest of this isn't going to work...
if [ $? -ne 0 ]; then
    echo "apt failed to install all required dependencies"
    exit
fi

# Set SERVER to be the preferred download server from the Apache CDN
SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"

# Download Guacamole Server
wget -O guacamole-server-${GUACVERSION}.tar.gz ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    echo "Failed to download guacamole-server-${GUACVERSION}.tar.gz"
    echo "${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz"
    exit
fi

# Download Guacamole Client
wget -O guacamole-${GUACVERSION}.war ${SERVER}/binary/guacamole-${GUACVERSION}.war
if [ $? -ne 0 ]; then
    echo "Failed to download guacamole-${GUACVERSION}.war"
    echo "${SERVER}/binary/guacamole-${GUACVERSION}.war"
    exit
fi

# Download Guacamole authentication extensions
wget -O guacamole-auth-jdbc-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz
if [ $? -ne 0 ]; then
    echo "Failed to download guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    echo "${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz"
    exit
fi

# Extract Guacamole files
tar -xzf guacamole-server-${GUACVERSION}.tar.gz
tar -xzf guacamole-auth-jdbc-${GUACVERSION}.tar.gz

# Make directories
mkdir -p /etc/guacamole/lib
mkdir -p /etc/guacamole/extensions

# Install guacd
cd guacamole-server-${GUACVERSION}
./configure --with-init-dir=/etc/init.d
make
make install
ldconfig
systemctl enable guacd
cd ..

# Get build-folder
BUILD_FOLDER=$(dpkg-architecture -qDEB_BUILD_GNU_TYPE)

# Move files to correct locations
mv guacamole-${GUACVERSION}.war /etc/guacamole/guacamole.war
ln -s /etc/guacamole/guacamole.war /var/lib/${TOMCAT}/webapps/
ln -s /usr/local/lib/freerdp/guac*.so /usr/lib/${BUILD_FOLDER}/freerdp/
ln -s /usr/share/java/mysql-connector-java.jar /etc/guacamole/lib/
cp guacamole-auth-jdbc-${GUACVERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACVERSION}.jar /etc/guacamole/extensions/

# Configure guacamole.properties
echo "mysql-hostname: $guacmysqlhostname" >> /etc/guacamole/guacamole.properties
echo "mysql-port: $guacmysqlport" >> /etc/guacamole/guacamole.properties
echo "mysql-database: $guacmysqldatabase" >> /etc/guacamole/guacamole.properties
echo "mysql-username: $guacmysqlusername" >> /etc/guacamole/guacamole.properties
echo "mysql-password: $guacdbuserpassword" >> /etc/guacamole/guacamole.properties

# restart tomcat
service ${TOMCAT} restart

# Create guacamole_db and grant guacamole_user permissions to it

# SQL code
SQLCODE="
create database $guacmysqldatabase;
GRANT SELECT,INSERT,UPDATE,DELETE ON $guacmysqldatabase.* TO '$guacmysqlusername'@'*';
flush privileges;"

# Execute SQL code
echo $SQLCODE | mysql -h $guacmysqlhostname -u $guacmysqlusername -p$guacdbuserpassword

# Add Guacamole schema to newly created database
cat guacamole-auth-jdbc-${GUACVERSION}/mysql/schema/*.sql | mysql -h $guacmysqlhostname -u $guacmysqlusername -p$guacdbuserpassword $guacmysqldatabase

# Ensure guacd is started
service guacd start

# Cleanup
rm -rf guacamole-*

echo -e "Installation Complete\nhttp://localhost:8080/guacamole/\nDefault login guacadmin:guacadmin\nBe sure to change the password."

# Install and configure NGINX
apt install --yes nginx-core
cat <<'EOT' > /etc/nginx/sites-enabled/default
# Nginx Config
    server {
        listen 80;
        server_name _;
        location / {
                proxy_pass http://localhost:8080/;
                proxy_buffering off;
                proxy_http_version 1.1;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection \$http_connection;
                access_log off;
        }
}
EOT

# Restart NGINX & Tomcat
systemctl restart nginx
systemctl restart tomcat8.service

# Change to call guacamole directly at "/" instead of "/guacamole"
/bin/rm -rf /var/lib/tomcat7/webapps/ROOT/* && /bin/cp -pr /var/lib/tomcat8/webapps/guacamole/* /var/lib/tomcat8/webapps/ROOT/
