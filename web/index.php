<?php
/*
 * Navbot StuckBot Visualiser v1.0
 * Parses DoD logs into KeyValues for stuck bots and allows download.
 */

if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['logText'])) {
    $logText = $_POST['logText'];
    $lines = explode("\n", $logText);

    $output = [];
    $currentMap = '';
    $mapKnown = false;

    foreach ($lines as $line) {
        $line = trim($line);

        // Map change
        if (preg_match('/\[SM\] Changed map to "(.*)"/', $line, $matches)) {
            $currentMap = $matches[1];
            $mapKnown = true;
            continue;
        }

        // Server start / NavBot initialization messages
        if (preg_match('/\[NavBot\] (CBasePlayer::PlayerRunCommand hook enabled|Loaded bot difficulty profiles|Extension fully loaded|Registered \d+ natives)\./', $line)) {
            $mapKnown = false;
            continue;
        }

        // NavBot suicide with coordinates, only if we know the map
        if ($mapKnown && preg_match('/\[NavBot\] Bot ".*" suicided due to being stuck for too long\. ([\-\d\.]+) ([\-\d\.]+) ([\-\d\.]+)/', $line, $matches)) {
            $output[] = [
                'map' => $currentMap,
                'x' => $matches[1],
                'y' => $matches[2],
                'z' => $matches[3]
            ];
        }
    }

    // Prepare KeyValues content
    $kvContent = "\"StuckBots\"\n{\n";
    foreach ($output as $index => $bot) {
        $kvContent .= "    \"$index\"\n    {\n";
        $kvContent .= "        \"map\"        \"" . $bot['map'] . "\"\n";
        $kvContent .= "        \"x\"          \"" . $bot['x'] . "\"\n";
        $kvContent .= "        \"y\"          \"" . $bot['y'] . "\"\n";
        $kvContent .= "        \"z\"          \"" . $bot['z'] . "\"\n";
        $kvContent .= "    }\n";
    }
    $kvContent .= "}\n";

    // If user clicked download, send headers and output file **before any HTML**
    if (isset($_POST['download'])) {
        header('Content-Type: text/plain');
        header('Content-Disposition: attachment; filename="locations.txt"');
        echo $kvContent;
        exit; // important to stop further HTML output
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Navbot StuckBot Visualiser v1.0</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 2em; }
        textarea { width: 100%; height: 300px; }
        pre { background: #f4f4f4; padding: 1em; white-space: pre-wrap; }
        button { padding: 0.5em 1em; font-size: 1em; }
    </style>
</head>
<body>
    <h1>Navbot StuckBot Visualiser v1.0</h1>
    <form method="post">
        <label for="logText">Paste your log here:</label><br>
        <textarea id="logText" name="logText"><?php echo isset($_POST['logText']) ? htmlspecialchars($_POST['logText']) : ''; ?></textarea><br><br>
        <button type="submit" name="analyze">Analyze</button>
        <?php if (!empty($_POST['logText'])): ?>
            <button type="submit" name="download">Download KeyValues</button>
        <?php endif; ?>
    </form>

<?php
// Display output on screen if not downloading
if (!empty($kvContent)) {
    echo "<h2>KeyValues Output</h2><pre>" . htmlspecialchars($kvContent) . "</pre>";
}
?>
</body>
</html>
