<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Apache Web Server Information</title>
</head>
<body>
    <h1>Apache Web Server Information</h1>
    <p>
        <ul>
            <li><strong>Pod name</strong>: <?php echo gethostname(); ?></li>
            <li><strong>Node name</strong>: <?php echo getenv('NODE_NAME') ?></li>
        </ul>    
</body>
</html>