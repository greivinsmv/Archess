; Headless tests of the exact selection/move procedures used by the GUI.
GuiSelfTest PROC USES ebx esi edi
    call StartLocal
    invoke ChooseSquare,12
    cmp selected,12
    jne gt_fail
    cmp legalSquares[20],1
    jne gt_fail
    cmp legalSquares[28],1
    jne gt_fail
    xor ecx,ecx
    xor edx,edx
gt_count:
    movzx eax,legalSquares[ecx]
    add edx,eax
    inc ecx
    cmp ecx,64
    jb gt_count
    cmp edx,2
    jne gt_fail
    invoke ChooseSquare,28
    mov eax,12
    call ObtenerPieza
    cmp al,'.'
    jne gt_fail
    mov eax,28
    call ObtenerPieza
    cmp al,'P'
    jne gt_fail
    call ObtenerTurno
    cmp eax,1
    jne gt_fail
    invoke ChooseSquare,8
    cmp selected,-1
    jne gt_fail
    invoke ChooseSquare,52
    invoke ChooseSquare,36
    mov eax,36
    call ObtenerPieza
    cmp al,'p'
    jne gt_fail
    invoke ChooseSquare,6
    cmp legalSquares[21],1
    jne gt_fail
    cmp legalSquares[23],1
    jne gt_fail
    cmp legalSquares[12],1
    jne gt_fail
    ; Pinned rook may move along the pin but cannot expose its king.
    xor ecx,ecx
gt_clear:
    mov eax,ecx
    mov bl,'.'
    call ColocarPieza
    inc ecx
    cmp ecx,64
    jb gt_clear
    mov eax,4
    mov bl,'K'
    call ColocarPieza
    mov eax,56
    mov bl,'k'
    call ColocarPieza
    mov eax,12
    mov bl,'R'
    call ColocarPieza
    mov eax,60
    mov bl,'r'
    call ColocarPieza
    call IniciarTurnos
    mov selected,-1
    invoke ChooseSquare,12
    cmp legalSquares[13],0
    jne gt_fail
    cmp legalSquares[20],1
    jne gt_fail
    ; Reset selection must remove old hints.
    invoke ChooseSquare,12
    cmp selected,-1
    jne gt_fail
    cmp legalSquares[20],0
    jne gt_fail
    xor eax,eax
    ret
gt_fail:
    mov eax,1
    ret
GuiSelfTest ENDP

.data
INCLUDE gui_fixtures.inc
.code
GuiFixtureTest PROC USES ebx esi edi ebp
    mov ebp,OFFSET fixtures
    mov edi,1
gf_case:
    mov eax,[ebp]
    call EstablecerTurno
    mov eax,[ebp+4]
    mov edx,[ebp+8]
    call EstablecerReglasRemotas
    xor ecx,ecx
gf_board:
    mov eax,ecx
    mov bl,BYTE PTR [ebp+16+ecx]
    call ColocarPieza
    inc ecx
    cmp ecx,64
    jb gf_board
    mov eax,[ebp+12]
    mov selected,eax
    call ComputeLegal
    xor ecx,ecx
gf_compare:
    mov al,legalSquares[ecx]
    cmp al,BYTE PTR [ebp+80+ecx]
    jne gf_fail
    inc ecx
    cmp ecx,64
    jb gf_compare
    add ebp,144
    inc edi
    cmp edi,fixtureCount
    jbe gf_case
    xor eax,eax
    ret
gf_fail:
    mov eax,edi
    add eax,100
    ret
GuiFixtureTest ENDP
