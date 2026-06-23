@echo off
cd /d L:\Development\openssh-portable\bin\x64\Release
echo === ssh -V ===
ssh.exe -V
echo === Match localnetwork 127.0.0.0/8 (expect compression yes) ===
> L:\Development\m1.txt echo Match localnetwork 127.0.0.0/8
>> L:\Development\m1.txt echo     Compression yes
ssh.exe -G -F L:\Development\m1.txt dummy 2>nul | findstr /I compression
echo === Match localnetwork 203.0.113.0/24 (expect compression no) ===
> L:\Development\m2.txt echo Match localnetwork 203.0.113.0/24
>> L:\Development\m2.txt echo     Compression yes
ssh.exe -G -F L:\Development\m2.txt dummy 2>nul | findstr /I compression
