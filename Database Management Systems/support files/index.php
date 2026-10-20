<?php require_once("db.php"); ?>
<html>
	<head>
		<title>OCTOPUS TERRITORY</title>
	</head>
	
	<body>
		OCTOPUS TERRITORY<p/>

<?php
	if ($_POST && isset($_POST["team"]) && $_POST["team"] != "")
	{
		$name = $_POST["team"];

		// PHP 8.1+ throws mysqli_sql_exception on errors; show the message instead of a blank page
		try
		{
			db_connect();
			$q = db_query("SELECT `name`,`score` FROM teams WHERE `name`='$name'");
			while ($r = db_fetch($q, "num"))
			{
				$name = $r[0];
				$score = $r[1];
				echo "\t\t$name, your score is $score!<br/>\n";
			}
		}
		catch (mysqli_sql_exception $e)
		{
			echo "\t\tQuery error: " . $e->getMessage() . "<br/>\n";
		}
	}
	else
	{
		echo <<< END
		<form method="post" action="">
			Team name: <input type="text" name="team"/>
			<input type="submit" value="Submit Query"/>
		</form>

END;
	}
?>
	</body>
</html>
