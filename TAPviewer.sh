#!/bin/bash
# (c) 2022 Leif Sawyer
# License: GPL 3.0 (see https://github.com/akhepcat/)
# Permanent home:  https://github.com/akhepcat/Miscellaneous/
# Direct download: https://raw.githubusercontent.com/akhepcat/Miscellaneous/master/TAPviewer.sh
# 
trap do_exit SIGINT SIGTERM SIGKILL SIGQUIT SIGABRT SIGSTOP SIGSEGV

do_exit() {
	ls -alF "${FILE}"
	exit 0
}
	

CWD=$(pwd)

FILE="markdown.html"

cat <<EOF > $FILE
<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Twitter markdown in the browser</title>
</head>
<body>

  <div id="form">
    <form name='myform'>
    <label>Select file:</label>
    <select id="fileOpt" name="fileOpt" class="drop_down">
      <div name='options'>
EOF
### End of Header

for i in $(/bin/ls -1 *.md | sort -h)
do
	echo "<option id='fileOpt' value=\"$i\">$i</option>" >> $FILE
done

cat <<EOF >>$FILE
      </div>
    </select>
    
  <button onclick="docOpen(); return false;">Open</button>
  </div>

  <div id="content"></div>
  <script src="marked.min.js"></script>
  <script>
     
     function docOpen(){
            var fSelect = document.getElementById('fileOpt');
            var fileOpt = fSelect.options[fSelect.selectedIndex].value;

            var client = new XMLHttpRequest();
            client.open('GET', fileOpt);
            client.onreadystatechange = function() {
              document.getElementById('content').innerHTML = marked.parse(client.responseText);
            }
            client.send();
     }
  </script>
</body>
</html>
EOF

# END of page

if [ -n "$(which http-server)" ]
then
	# Pop open a window, try not to allow raw browsing, even though we're 'chrooted' into a temp directory
	http-server -id --no-dotfiles --silent -o "${FILE}"

elif [ -n "$(which python3)" ]
then
	echo "browse to http://localhost:8080/${FILE}"
	python3 -m http.server --directory "${CWD}"
else
	echo "You'll need to copy all the .md files, as well as the following file to a webserver to view them"
fi

do_exit
