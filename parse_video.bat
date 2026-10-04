@echo off
chcp 65001 >nul 2>&1
setlocal

REM ==== 调用 aida-video-parser 的 parse.py ====
REM 用法：1) 把视频文件拖到本脚本上；2) 或双击本脚本后在提示处输入路径
set "PY_SCRIPT=C:\Users\LENOVO\.codebuddy\skills\aida-video-parser\scripts"
set "PYEXE=python"

REM --- 1. 取路径：命令行参数（含拖拽）优先，否则提示输入 ---
set "TARGET=%~1"
if not defined TARGET set /p "TARGET=请输入视频路径："
if not defined TARGET (
  echo [错误] 没有输入路径，已退出。
  pause
  exit /b 1
)
set "TARGET=%TARGET:"=%"

REM --- 2. 检查 python（找不到 python 时退回 py -3 启动器） ---
where python >nul 2>&1
if errorlevel 1 set "PYEXE=py -3"
%PYEXE% --version >nul 2>&1
if errorlevel 1 (
  echo [错误] 未找到 Python，请先安装 Python 3 并加入 PATH。
  pause
  exit /b 1
)

REM --- 3. 检查被调用的脚本是否存在 ---
if not exist "%PY_SCRIPT%" (
  echo [错误] 找不到脚本：%PY_SCRIPT%
  echo         请先创建该文件，再运行本脚本。
  pause
  exit /b 1
)

REM --- 4. 执行 ---
echo 执行命令：%PYEXE% "%PY_SCRIPT%" "%TARGET%"
echo ------------------------------------------------------------
%PYEXE% "%PY_SCRIPT%" "%TARGET%"
set "EXITCODE=%errorlevel%"
echo ------------------------------------------------------------
echo 执行结束，退出码：%EXITCODE%
pause
exit /b %EXITCODE%
