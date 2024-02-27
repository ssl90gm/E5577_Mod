rd /S /Q dist

7z a -tgzip dist\app\webroot\WebApp\common\html\header.html.gz dev\app\webroot\WebApp\common\html\header.html
7z a -tgzip dist\app\webroot\WebApp\common\css\openvpn.css.gz dev\app\webroot\WebApp\common\css\openvpn.css

xcopy /E /I dev\app\bin dist\app\bin
xcopy /E /I dev\system dist\system
xcopy /E /I dev\online dist\online
xcopy /E /I dev\app\webroot\httpd_root dist\app\webroot\httpd_root
xcopy /E /I dev\app\webroot\WebApp\common\res dist\app\webroot\WebApp\common\res

cd dist
..\7z a -ttar ..\install\install.tar system app online

..\7z a -tgzip ..\install\install.tgz ..\install\install.tar
del ..\install\install.tar

cd ..
pause