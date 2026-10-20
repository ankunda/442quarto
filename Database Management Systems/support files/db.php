<?php

/**********************
 * db.php             *
 *                    *
 * Database functions *
 **********************/

// make sure that this file cannot be directly accessed
if (stristr(htmlentities($_SERVER["PHP_SELF"]), "db.php")) {
    header("Location: index.php");
    exit();
}

require_once("config.php");

/**********************
 * DATABASE FUNCTIONS *
 **********************/

function db_connect()
{
	global $_ADMIN, $conn;

	$conn = new mysqli($_ADMIN["MYSQL_URL"], $_ADMIN["MYSQL_USER"], $_ADMIN["MYSQL_PASS"], $_ADMIN["MYSQL_DATABASE"]);

	if ($conn->connect_errno)
		trigger_error($conn->connect_error);
}

function db_query($query)
{
	global $conn;

	$q = $conn->query($query);
	if (!$q)
		trigger_error($conn->error);

	return $q;
}

function db_multi_query($query)
{
	global $conn;

	$q = $conn->multi_query($query);
	if (!$q)
		trigger_error($conn->error);

	return $q;
}

function db_rows($q)
{
	return $q->num_rows;
}

function db_fetch($q, $n)
{
	if ($n == "num")
		return $q->fetch_row();
	else
		return $q->fetch_assoc();
}

function db_fetch_all($q)
{
	return $q->fetch_all();
}

function db_multi_fetch($q)
{
	global $conn;

	while ($conn->more_results())
	{
		$conn->next_result();
		if ($r = $conn->store_result())
			$r->free();
	}
}

function db_free($q)
{
	if ($q)
		$q->free();
}

?>
