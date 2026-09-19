@echo off
cd /d "D:\project x\tripmate_app"
set NO_PROXY=localhost,127.0.0.1
"C:\Users\FT-0006\Downloads\flutter_windows_3.44.4-stable\flutter\bin\flutter.bat" run -d chrome --web-port=5555 --verbose > "D:\project x\tripmate_app\chrome-run.log" 2>&1
