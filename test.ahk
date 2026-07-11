WinGetClientPos(&cx, &cy, &cw, &ch, "Antigravity IDE")
WinGetPos(&wx, &wy, &ww, &wh, "Antigravity IDE")
FileAppend("Client: " cx ", " cy ", " cw ", " ch "`nWindow: " wx ", " wy ", " ww ", " wh, "test_out.txt")
