CREATE DATABASE cyberdb;
CREATE USER 'cyberadmin'@'localhost' IDENTIFIED BY 'Cyber!1234';
GRANT ALL PRIVILEGES ON cyberdb.* TO 'cyberadmin'@'localhost';