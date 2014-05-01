$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"

function CopyBoostDlls($vsVersion, $outputPath, $boostLibs)
{
    foreach ($boostLib in $boostLibs)
    {
        copy "$ENV:BOOST_LIBRARYDIR\boost_$boostLib-vc$($vsVersion.Replace('.', ''))-mt-[1-9]*.dll" "$outputPath"
    }
}

function BuildZLib($buildDir, $outputPath, $zlibBase, $cmakeGenerator, $setBuildEnvVars=$true)
{
    $zlibUrl = "http://zlib.net/$zlibBase.tar.gz"
    $zlibPath = "$ENV:TEMP\$zlibBase.tar.gz"

    pushd .
    try
    {
        cd "$buildDir"

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($zlibUrl, $zlibPath) }
        Expand7z $zlibPath
        del $zlibPath
        Expand7z "$zlibBase.tar"
        del "$zlibBase.tar"

        cd "$zlibBase"

        &cmake . -G $cmakeGenerator
        if ($LastExitCode) { throw "cmake failed" }

        &msbuild zlib.sln /p:Configuration=Release
        if ($LastExitCode) { throw "msbuild failed" }

        copy "Release\*.dll" $outputPath

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$zlibBase"
            $ENV:LIB += ";$buildDir\$zlibBase\Release"
        }
    }
    finally
    {
        popd
    }
}


function BuildLibPNG($buildDir, $outputPath, $libpngBase, $cmakeGenerator, $setBuildEnvVars=$true)
{
    $libpngUrl = "http://download.sourceforge.net/libpng/$libpngBase.zip"
    $libpngPath = "$ENV:Temp\$libpngBase.zip"

    pushd .
    try
    {
        cd "$buildDir"

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($libpngUrl, $libpngPath) }
        Expand7z $libpngPath
        del $libpngPath

        cd $libpngBase

        &cmake . -G $cmakeGenerator
        if ($LastExitCode) { throw "cmake failed" }

        &msbuild libpng.sln /p:Configuration=Release
        if ($LastExitCode) { throw "msbuild failed" }

        copy "Release\*.dll" $outputPath

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$libpngBase"
            $ENV:LIB += ";$buildDir\$libpngBase\Release"
        }
    }
    finally
    {
        popd
    }
}


function GetCPPRestSDK($vsVersion, $buildDir, $outputPath, $cpprestsdkVersion, $cpprestsdkArch, $setBuildEnvVars=$true)
{
    $nugetUrl = "http://nuget.org/nuget.exe"

    pushd .
    try
    {
        cd $buildDir

        $cpprestsdkVSVersion = $vsVersion.Replace(".", "")
        $cpprestsdkBase="cpprestsdk.$cpprestsdkVersion"

        $nugetPath = "$buildDir\nuget.exe"
        if (!(Test-Path $nugetPath))
        {
            ExecRetry { (new-object System.Net.WebClient).DownloadFile($nugetUrl, $nugetPath) }
        }

        ExecRetry {
            &$nugetPath install cpprestsdk -version "$cpprestsdkVersion"
            if ($LastExitCode) { throw "NuGet failed" }
        }

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$cpprestsdkBase\build\native\include"
            $ENV:LIB += ";$buildDir\$cpprestsdkBase\build\native\lib\$cpprestsdkArch\v$cpprestsdkVSVersion\Release\Desktop"
        }

        copy "$buildDir\$cpprestsdkBase\build\native\bin\$cpprestsdkArch\v$cpprestsdkVSVersion\Release\Desktop\*.dll" $outputPath
    }
    finally
    {
        popd
    }
}


function BuildOpenSSL($buildDir, $outputPath, $opensslVersion, $cmakeGenerator, $runTests=$true)
{
    $opensslBase = "openssl-$opensslVersion"
    $opensslPath = "$ENV:Temp\$opensslBase.tar.gz"
    $opensslUrl = "http://www.openssl.org/source/$opensslBase.tar.gz"

    pushd .
    try
    {
        cd $buildDir

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($opensslUrl, $opensslPath) }
        Expand7z $opensslPath
        del $opensslPath
        Expand7z "$opensslBase.tar"
        del "$opensslBase.tar"

        cd $opensslBase
        &cmake . -G $cmakeGenerator

        &perl Configure VC-WIN32 --prefix="$ENV:OPENSSL_ROOT_DIR"
        if ($LastExitCode) { throw "perl failed" }

        ms\do_nasm
        if ($LastExitCode) { throw "do_nasm failed" }

        &nmake -f ms\ntdll.mak
        if ($LastExitCode) { throw "nmake failed" }

        if($runTests)
        {
            &nmake -f ms\ntdll.mak test
            if ($LastExitCode) { throw "nmake test failed" }
        }

        &nmake -f ms\ntdll.mak install
        if ($LastExitCode) { throw "nmake install failed" }

        copy "$ENV:OPENSSL_ROOT_DIR\bin\*.dll" $outputPath
        copy "$ENV:OPENSSL_ROOT_DIR\bin\*.exe" $outputPath
    }
    finally
    {
        popd
    }
}


function BuildFreeRDP($buildDir, $outputPath, $patchesPath, $cmakeGenerator, $monolithicBuild=$true,
                      $buildSharedLibs=$true, $setBuildEnvVars=$true)
{
    $freeRDPdir = "FreeRDP"
    $freeRDPUrl = "https://github.com/FreeRDP/FreeRDP.git"

    pushd .
    try
    {
        cd $buildDir
        ExecRetry { GitClonePull $freeRDPdir $freeRDPUrl }
        cd $freeRDPdir

        if($monolithicBuild) { $monolithicBuildStr = "ON" } else { $monolithicBuildStr = "OFF" }
        if($buildSharedLibs) { $buildSharedLibsStr = "ON" } else { $buildSharedLibsStr = "OFF" }

        &cmake . -DBUILD_SHARED_LIBS=ON -G $cmakeGenerator -DMONOLITHIC_BUILD="$monolithicBuildStr" -DDBUILD_SHARED_LIBS="$buildSharedLibs"
        if ($LastExitCode) { throw "cmake failed" }

        &git am "$patchesPath\0001-Fix-VS-12-compilation-bug.patch"
        if ($LastExitCode) { throw "git am failed" }

        &msbuild FreeRDP.sln /p:Configuration=Release
        if ($LastExitCode) { throw "MSBuild failed" }

        copy "Release\*.dll" $outputPath
        copy "Release\*.exe" $outputPath

        # Verify that FreeRDP runs properly so when know that all dependencies are in place
        $p = Start-Process -Wait -PassThru -NoNewWindow "$outputPath\wfreerdp.exe"
        if($p.ExitCode)
        {
            throw "wfreerdp test run failed with exit code: $($p.ExitCode)"
        }

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$freeRDPdir\include"
            $ENV:INCLUDE += ";$buildDir\$freeRDPdir\winpr\include"
            $ENV:LIB += ";$buildDir\$freeRDPdir\Release"
        }
    }
    finally
    {
        popd
    }
}


function BuildPthreadsW32($buildDir, $outputPath, $pthreadsWin32Base, $setBuildEnvVars=$true)
{
    $pthreadsWin32Url = "ftp://sourceware.org/pub/pthreads-win32/$pthreadsWin32Base.zip"
    $pthreadsWin32Path = "$ENV:Temp\$pthreadsWin32Base.zip"

    pushd .
    try
    {
        cd $buildDir
        mkdir $pthreadsWin32Base
        cd $pthreadsWin32Base

        ExecRetry { (new-object System.Net.WebClient).DownloadFile($pthreadsWin32Url, $pthreadsWin32Path) }
        Expand7z $pthreadsWin32Path
        del $pthreadsWin32Path

        cd "pthreads.2"

        &nmake clean VC
        if ($LastExitCode) { throw "nmake failed" }

        copy "pthreadVC2.dll" "$outputPath"

        if($setBuildEnvVars)
        {
            $ENV:INCLUDE += ";$buildDir\$pthreadsWin32Base\pthreads.2"
            $ENV:THREADS_PTHREADS_WIN32_LIBRARY = "$buildDir\$pthreadsWin32Base\pthreads.2\pthreadVC2.lib"
        }
    }
    finally
    {
        popd
    }
}


function BuildEHS($buildDir, $outputPath, $cmakeGenerator, $pthreadsW32Lib, $setBuildEnvVars=$true)
{
    $ehsDir = "EHS"
    $ehsUrl = "https://github.com/cezarboicu/EHS.git"

    pushd .
    try
    {
        cd $buildDir
        ExecRetry { GitClonePull $ehsDir $ehsUrl }
        cd $ehsDir

        &cmake . -G $cmakeGenerator -DTHREADS_PTHREADS_WIN32_LIBRARY="$pthreadsW32Lib"
        if ($LastExitCode) { throw "cmake failed" }

        &msbuild ehs.sln /p:Configuration=Release
        if ($LastExitCode) { throw "MSBuild failed" }

        if($setBuildEnvVars)
        {
            $ehsRootDir = "$buildDir\$ehsDir"
            $ENV:EHS_ROOT_DIR = $ehsRootDir
            $ENV:INCLUDE += ";$ehsRootDir"
            $ENV:LIB += ";$ehsRootDir\Release"
        }
    }
    finally
    {
        popd
    }
}


function BuildFreeRDPWebConnect($buildDir, $outputPath, $cmakeGenerator, $pthreadsW32Lib, $ehsRootDir)
{
    $freeRDPWebConnectDir = "FreeRDP-WebConnect"
    $freeRDPWebConnectUrl = "https://github.com/cloudbase/FreeRDP-WebConnect.git"

    pushd .
    try
    {
        cd $buildDir
        ExecRetry { GitClonePull $freeRDPWebConnectDir $freeRDPWebConnectUrl }
        cd "$freeRDPWebConnectDir\wsgate"

        &cmake . -G $cmakeGenerator -DTHREADS_PTHREADS_WIN32_LIBRARY="$pthreadsW32Lib" -DEHS_ROOT_DIR="$ehsRootDir"
        if ($LastExitCode) { throw "cmake failed" }

        &msbuild wsgate.sln /p:Configuration=Release
        if ($LastExitCode) { throw "MSBuild failed" }

        copy "Release\wsgate.exe" $outputPath

        # Verify that wsgate runs properly so when know that all dependencies are in place
        $p = Start-Process -Wait -PassThru -NoNewWindow "$outputPath\wsgate.exe" -ArgumentList "-V"
        if($p.ExitCode)
        {
            throw "wsgate test run failed with exit code: $($p.ExitCode)"
        }
    }
    finally
    {
        popd
    }
}