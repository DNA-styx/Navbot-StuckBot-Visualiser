<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>DoD Log Map & Bot Locations KeyValues</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2em; }
        textarea { width: 100%; height: 300px; }
        pre { background: #f4f4f4; padding: 1em; white-space: pre-wrap; }
    </style>
</head>
<body>
    <h1>DoD Log Map & Bot Locations KeyValues</h1>
    <form method="post">
        <label for="logText">Paste your log here:</label><br>
        <textarea id="logText" name="logText"><?php echo isset($_POST['logText']) ? htmlspecialchars($_POST['logText']) : ''; ?></textarea><br><br>
        <button type="submit">Analyze</button>
    </form>

<?php
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['logText'])) {
    $logText = $_POST['logText'];
    $lines = explode("\n", $logText);

    $output = [];
    $currentMap = '';

    foreach ($lines as $line) {
        $line = trim($line);

        // Map change
        if (preg_match('/\[SM\] Changed map to "(.*)"/', $line, $matches)) {
            $currentMap = $matches[1];
        }

        // NavBot suicide with coordinates
        if ($currentMap && preg_match('/\[NavBot\] Bot ".*" suicided due to being stuck for too long\. ([\-\d\.]+) ([\-\d\.]+) ([\-\d\.]+)/', $line, $matches)) {
            $output[] = [
                'map' => $currentMap,
                'x' => $matches[1],
                'y' => $matches[2],
                'z' => $matches[3]
            ];
        }
    }

    // Output as KeyValues
    echo "<h2>KeyValues Output</h2><pre>";
    echo "\"StuckBots\"\n{\n";
    foreach ($output as $index => $bot) {
        echo "    \"$index\"\n    {\n";
        echo "        \"map\"        \"" . $bot['map'] . "\"\n";
        echo "        \"x\"          \"" . $bot['x'] . "\"\n";
        echo "        \"y\"          \"" . $bot['y'] . "\"\n";
        echo "        \"z\"          \"" . $bot['z'] . "\"\n";
        echo "    }\n";
    }
    echo "}\n";
    echo "</pre>";
}
?>
</body>
</html>
