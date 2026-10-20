<?php

/********************************************************
 * config.php                                           *
 *                                                      *
 * This is the database configuration for the web site. *
 ********************************************************/

// make sure that this file cannot be directly accessed
if (stristr(htmlentities($_SERVER["PHP_SELF"]), "config.php")) {
    header("Location: index.php");
    exit();
}

// database options
$_ADMIN["MYSQL_URL"] = "localhost";	// generally, this will be localhost
$_ADMIN["MYSQL_USER"] = "cyberadmin";	// the mysql database user
$_ADMIN["MYSQL_PASS"] = "Cyber!1234";	// the mysql database password
$_ADMIN["MYSQL_DATABASE"] = "cyberdb";	// the database name

/**********************************
 * DO NOT EDIT THE OPTIONS BELOW! *
 **********************************/

if (!isset($_ADMIN) ||
    !isset($_ADMIN["MYSQL_URL"]) ||
    !isset($_ADMIN["MYSQL_USER"]) ||
    !isset($_ADMIN["MYSQL_PASS"]) ||
    !isset($_ADMIN["MYSQL_DATABASE"]))
	if (!isset($_ADMIN["ERROR"]))
		die("ERROR: Configuration not properly defined.");
	else
		die($_ADMIN["ERROR"]);

?>
