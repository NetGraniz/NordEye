#Requires AutoHotkey v2.0
#SingleInstance Force

; NordEye — single-file Windows utility (AutoHotkey v2, native GDI+).
; The complete panel is painted as one image: no rectangular native dropdown/buttons.

CoordMode "Mouse", "Screen"

global running := false
global reminderActive := false
global animationMode := 0      ; 0 hidden, 1 fade in, 2 fade out, 3 pulsing
global animationStart := 0
global animationFromAlpha := 0
global displayAlpha := 0
global reminderMinutes := 20
global intervalIndex := 3
global intervalValues := [5, 10, 20, 30, 45, 60]
global intervalLabels := ["5 минут", "10 минут", "20 минут", "30 минут", "45 минут", "60 минут"]
global overlays := []
global menuOpen := false
global menuGui := 0
global menuPanel := 0
global uiHeight := 332
global gdipToken := 0
global fontFamily := 0

global main := Gui("-Caption -Resize -DPIScale", "NordEye")
main.BackColor := "121C2A"
main.MarginX := 0
main.MarginY := 0
global panel := main.AddPicture("x0 y0 w432 h332 +0x100")
panel.OnEvent("Click", HandlePanelClick)
main.OnEvent("Close", CloseApp)
main.OnEvent("Escape", CloseMenu)
OnMessage(0x0201, HandleMouseDown)

A_IconTip := "NordEye — отдых для глаз"
A_TrayMenu.Delete()
A_TrayMenu.Add("Открыть NordEye", ShowApp)
A_TrayMenu.Add()
A_TrayMenu.Add("Выход", (*) => ExitApp())
A_TrayMenu.Default := "Открыть NordEye"
A_TrayMenu.ClickCount := 1

StartGraphics()
CreateOverlays()
main.Show("w432 h332")
RoundMain()
DrawPanel()
CreateDropdown()
OnExit Cleanup

; ------------ Interface ------------

StartGraphics() {
    global gdipToken, fontFamily
    startup := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut "UInt", 1, startup, 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdipToken, "Ptr", startup, "Ptr", 0)
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fontFamily)
}

DrawPanel() {
    global panel, intervalIndex, intervalLabels, running
    ; Same window size as NordCursor: 432 x 332, without resizing for the menu.
    w := 432, h := 332
    bitmap := 0, graphics := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0
        , "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF121B29)

    ; Subtle multi-layer glow of the whole panel.
    for idx, color in [0x0C77CFFF, 0x1668BDFF, 0x295D99D2] {
        offset := 5 - idx
        Outline(graphics, offset, offset, w - 2*offset, h - 2*offset, 16, color, 1.2)
    }
    Outline(graphics, 1, 1, w - 2, h - 2, 16, 0xFF314258, 1.1)
    Outline(graphics, 2.5, 2.5, w - 5, h - 5, 16, 0x432787C3, 1.0)

    ; Title, status, minimize and close.
    EyeIcon(graphics, 25, 28, 0xFF18C3F7)
    TextAt(graphics, "NordEye", 72, 18, 230, 38, 21, 0xFFE9F4FF, true)
    TextAt(graphics, running ? "АКТИВНО" : "ГОТОВ К ЗАПУСКУ", 72, 47, 235, 18, 9
        , running ? 0xFF59DFAE : 0xFF7F94AD)
    Line(graphics, 365, 35, 375, 35, 0xFF8498B1, 1.7)
    Line(graphics, 398, 30, 408, 40, 0xFF8498B1, 1.7)
    Line(graphics, 408, 30, 398, 40, 0xFF8498B1, 1.7)

    ; A compact interval card and an actual rounded selector.
    Rounded(graphics, 22, 88, 388, 142, 15, 0xFF172438, 0xFF2D4763, 1)
    Outline(graphics, 24, 90, 384, 138, 14, 0x2447BFFF, 1)
    Rounded(graphics, 39, 104, 44, 44, 12, 0xFF1E3149, 0xFF335477, 1)
    ClockIcon(graphics, 61, 126, 0xFFC0D2EA)
    TextAt(graphics, "Интервал", 96, 102, 282, 24, 16, 0xFFE6F2FF, true)
    TextAt(graphics, "Напоминать каждые", 96, 126, 280, 22, 12, 0xFF869AB4)
    Rounded(graphics, 39, 165, 354, 45, 11, 0xFF1D2B40, 0xFF37618B, 1.2)
    Outline(graphics, 40.5, 166.5, 351, 42, 10, 0x3635C8F9, 1)
    TextAt(graphics, intervalLabels[intervalIndex], 57, 168, 260, 39, 15, 0xFFE9F4FF)
    Line(graphics, 359, 183, 365, 189, 0xFF9CB6D3, 2)
    Line(graphics, 365, 189, 371, 183, 0xFF9CB6D3, 2)

    ; Three buttons fit the exact 432 px width without squeezing labels.
    Line(graphics, 22, 246, 410, 246, 0xFF2A3B52, 1)
    Rounded(graphics, 22, 261, 142, 49, 11, 0xFF0EADE8, 0xFF32D9FF, 1.3)
    Outline(graphics, 24, 263, 138, 45, 10, 0x652AF0FF, 1)
    TextAt(graphics, running ? "✓ Запущено" : "▶ Запустить", 25, 263, 135, 45, 13, 0xFFFFFFFF, true, 1)
    Rounded(graphics, 174, 261, 99, 49, 11, 0xFF213149, 0xFF344C68, 1.1)
    Outline(graphics, 176, 263, 95, 45, 10, 0x252FAEF0, 1)
    TextAt(graphics, "Ⅱ Пауза", 176, 263, 95, 45, 12.5, 0xFFD8E6F8, false, 1)
    Rounded(graphics, 283, 261, 127, 49, 11, 0xFF213149, 0xFF344C68, 1.1)
    Outline(graphics, 285, 263, 123, 45, 10, 0x252FAEF0, 1)
    TextAt(graphics, "◉ Просмотр", 285, 263, 123, 45, 12.5, 0xFFD8E6F8, false, 1)

    bitmapHandle := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &bitmapHandle, "UInt", 0xFF121B29)
    panel.Value := "HBITMAP:*" bitmapHandle
    DllCall("gdi32\DeleteObject", "Ptr", bitmapHandle)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
}


; Draw a separate non-activating popup, not a resized main window.
; Its image is prepared while hidden, avoiding an unpainted first frame.
CreateDropdown() {
    global main, menuGui, menuPanel
    menuGui := Gui("-Caption +ToolWindow -DPIScale +Owner" main.Hwnd " +E0x08000000", "Интервал")
    menuGui.BackColor := "172638"
    menuGui.MarginX := 0
    menuGui.MarginY := 0
    menuPanel := menuGui.AddPicture("x0 y0 w354 h196 +0x100")
    menuPanel.OnEvent("Click", HandleMenuClick)
    menuGui.Show("Hide w354 h196")
    region := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", 355, "Int", 197, "Int", 24, "Int", 24, "Ptr")
    DllCall("user32\SetWindowRgn", "Ptr", menuGui.Hwnd, "Ptr", region, "Int", 0)
    DrawDropdown()
}

DrawDropdown() {
    global menuPanel, intervalLabels, intervalIndex
    bitmap := 0, graphics := 0, bitmapHandle := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 354, "Int", 196, "Int", 0
        , "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF172638)
    Rounded(graphics, 1, 1, 352, 194, 12, 0xFF172638, 0xFF395776, 1.3)
    for idx, label in intervalLabels {
        rowY := 7 + (idx - 1) * 30
        if idx = intervalIndex
            Rounded(graphics, 7, rowY, 340, 29, 7, 0xFF24445D, 0xFF3679A2, 1)
        TextAt(graphics, label, 20, rowY, 280, 29, 13
            , idx = intervalIndex ? 0xFF6DDEFF : 0xFFD4E4F6)
    }
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &bitmapHandle, "UInt", 0xFF172638)
    menuPanel.Value := "HBITMAP:*" bitmapHandle
    DllCall("gdi32\DeleteObject", "Ptr", bitmapHandle)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
}

OpenMenu() {
    global main, menuGui, menuOpen
    if menuOpen
        return
    menuOpen := true
    main.GetPos(&x, &y)
    menuGui.Show("NA x" (x + 39) " y" (y + 211) " w354 h196")
}

HandleMenuClick(*) {
    global menuGui, intervalIndex, intervalValues, reminderMinutes, running
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", menuGui.Hwnd, "Ptr", point)
    y := NumGet(point, 4, "Int")
    if y >= 7 && y < 187 {
        index := Floor((y - 7) / 30) + 1
        if index >= 1 && index <= 6 && index != intervalIndex {
            intervalIndex := index
            reminderMinutes := intervalValues[index]
            if running
                SetTimer ReminderTimer, reminderMinutes * 60000
            DrawPanel()
            DrawDropdown()
        }
    }
    CloseMenu()
}

Rounded(g, x, y, w, h, r, fill, border := 0, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", fill, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if border
        StrokePath(g, path, border, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

Outline(g, x, y, w, h, r, color, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    StrokePath(g, path, color, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

MakeRoundPath(x, y, w, h, r) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    d := r * 2
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y + h - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    return path
}

StrokePath(g, path, color, width) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

Line(g, x1, y1, x2, y2, color, width := 1) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

TextAt(g, str, x, y, w, h, size, color, bold := false, center := 0) {
    global fontFamily
    font := 0, brush := 0, fmt := 0
    DllCall("gdiplus\GdipCreateFont", "Ptr", fontFamily, "Float", size, "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x1000, "UShort", 0, "Ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", center)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    rect := Buffer(16, 0)
    NumPut "Float", x, rect, 0
    NumPut "Float", y, rect, 4
    NumPut "Float", w, rect, 8
    NumPut "Float", h, rect, 12
    DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", str, "Int", -1, "Ptr", font
        , "Ptr", rect, "Ptr", fmt, "Ptr", brush)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
}

EyeIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 3, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen, "Float", x, "Float", y+7
        , "Float", x+11, "Float", y-4, "Float", x+28, "Float", y-4, "Float", x+40, "Float", y+7)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen, "Float", x, "Float", y+7
        , "Float", x+11, "Float", y+19, "Float", x+28, "Float", y+19, "Float", x+40, "Float", y+7)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", x+15, "Float", y+1, "Float", 11, "Float", 11)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

ClockIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 2.1, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", x-13, "Float", y-13, "Float", 26, "Float", 26)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x, "Float", y-8, "Float", x, "Float", y)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x, "Float", y, "Float", x+6, "Float", y+4)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

RoundMain() {
    global main, uiHeight
    region := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", 433, "Int", uiHeight+1, "Int", 32, "Int", 32, "Ptr")
    DllCall("user32\SetWindowRgn", "Ptr", main.Hwnd, "Ptr", region, "Int", 1)
}

HandleMouseDown(wParam, lParam, msg, hwnd) {
    global main
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != main.Hwnd
        return
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", main.Hwnd, "Ptr", point)
    x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    if y < 70 && x < 350 {
        CloseMenu()
        DllCall("user32\ReleaseCapture")
        PostMessage 0xA1, 2,,, "ahk_id " main.Hwnd
    }
}

HandlePanelClick(*) {
    global main, menuOpen
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", main.Hwnd, "Ptr", point)
    x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    if y < 57 && x >= 386 {
        CloseApp()
        return
    }
    if y < 57 && x >= 351 {
        CloseMenu()
        main.Minimize()
        return
    }
    if menuOpen {
        CloseMenu()
        return
    }
    if x >= 39 && x <= 393 && y >= 165 && y <= 210
        OpenMenu()
    else if y >= 261 && y <= 310 {
        if x >= 22 && x <= 164
            StartReminder()
        else if x >= 174 && x <= 273
            PauseReminder()
        else if x >= 283 && x <= 410
            ShowReminder()
    }
}

CloseMenu(*) {
    global menuOpen, menuGui
    if menuOpen {
        menuOpen := false
        menuGui.Hide()
    }
}

CloseApp(*) {
    global main
    CloseMenu()
    main.Hide()
}

ShowApp(*) {
    global main
    main.Show("Restore")
    WinActivate "ahk_id " main.Hwnd
}

; ------------ Timer and reminder ------------

StartReminder(*) {
    global running, reminderMinutes
    running := true
    SetTimer ReminderTimer, reminderMinutes * 60000
    DrawPanel()
}

PauseReminder(*) {
    global running
    running := false
    SetTimer ReminderTimer, 0
    ; The current glow is deliberately NOT dismissed; Esc owns dismissal.
    DrawPanel()
}

ReminderTimer(*) {
    global running, reminderActive
    if running && !reminderActive
        ShowReminder()
}

ShowReminder(*) {
    global reminderActive, animationMode, animationStart, displayAlpha, overlays
    if reminderActive
        return
    reminderActive := true
    animationMode := 1
    animationStart := A_TickCount
    displayAlpha := 0
    for layer in overlays
        layer.gui.Show("NA")
    UpdateOverlays(0)
    SetTimer AnimateReminder, 33
}

HideReminder(*) {
    global reminderActive, animationMode, animationStart, animationFromAlpha, displayAlpha
    if !reminderActive || animationMode = 2
        return
    animationMode := 2
    animationStart := A_TickCount
    animationFromAlpha := displayAlpha
    SetTimer AnimateReminder, 33
}

AnimateReminder(*) {
    global animationMode, animationStart, animationFromAlpha, displayAlpha, reminderActive, overlays
    elapsed := A_TickCount - animationStart
    switch animationMode {
        case 1:
            portion := Min(1, elapsed / 500)
            displayAlpha := Round(255 * (1 - (1 - portion)**3))
            if portion = 1 {
                animationMode := 3
                animationStart := A_TickCount
            }
        case 2:
            portion := Min(1, elapsed / 650)
            displayAlpha := Round(animationFromAlpha * (1 - portion)**2)
            if portion = 1 {
                displayAlpha := 0
                reminderActive := false
                animationMode := 0
                for layer in overlays
                    layer.gui.Hide()
                SetTimer AnimateReminder, 0
            }
        case 3:
            phase := Mod(elapsed, 3400) / 3400
            displayAlpha := Round(173 + 82 * (0.5 + 0.5 * Sin(6.283185307179586 * phase)))
    }
    UpdateOverlays(displayAlpha)
}

; ------------ Click-through glow (cached ARGB image, opacity-only animation) ------------

CreateOverlays() {
    global overlays
    Loop MonitorGetCount() {
        MonitorGet A_Index, &left, &top, &right, &bottom
        width := right - left, height := bottom - top
        ; WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_LAYERED
        window := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000 +E0x80000")
        window.Show("Hide x" left " y" top " w" width " h" height)
        info := Buffer(40, 0)
        NumPut "UInt", 40, info, 0
        NumPut "Int", width, info, 4
        NumPut "Int", -height, info, 8
        NumPut "UShort", 1, info, 12
        NumPut "UShort", 32, info, 14
        dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
        pixels := 0
        bmp := DllCall("gdi32\CreateDIBSection", "Ptr", dc, "Ptr", info, "UInt", 0
            , "Ptr*", &pixels, "Ptr", 0, "UInt", 0, "Ptr")
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bmp, "Ptr")
        context := {gui: window, dc: dc, bitmap: bmp, old: old, bits: pixels
            , width: width, height: height, left: left, top: top
            , size: Buffer(8, 0), pos: Buffer(8, 0), src: Buffer(8, 0), blend: Buffer(4, 0)}
        BuildGradient(context)
        NumPut "Int", width, context.size, 0
        NumPut "Int", height, context.size, 4
        NumPut "Int", left, context.pos, 0
        NumPut "Int", top, context.pos, 4
        NumPut "UChar", 255, context.blend, 2
        NumPut "UChar", 1, context.blend, 3  ; AC_SRC_ALPHA
        overlays.Push(context)
    }
}

BuildGradient(layer) {
    w := layer.width, h := layer.height
    ; One cached, per-pixel ARGB glow: saturated blue at the bezel and
    ; an extended transparent feather into the screen. No four GUI strips.
    spread := Min(190, Floor(Min(w, h) / 3))
    if spread < 2
        return

    ; The gaussian core keeps the rim luminous; smoothstep adds a faint,
    ; long tail. Both curves meet zero smoothly at the inner boundary.
    colors := []
    gaussianEnd := Exp(-6)
    Loop spread {
        t := (A_Index - 1) / (spread - 1)
        gaussian := (Exp(-6*t*t) - gaussianEnd) / (1 - gaussianEnd)
        tail := 1 - (3*t*t - 2*t*t*t)
        a := Round(206 * (0.72*gaussian + 0.28*tail))
        ; Shift slightly from cyan at the edge toward cool blue inward.
        red := Round((28 + 10*t)*a/255)
        green := Round((187 - 52*t)*a/255)
        blue := Round((255 - 17*t)*a/255)
        colors.Push(blue | (green << 8) | (red << 16) | (a << 24))
    }

    DllCall("ntdll\RtlZeroMemory", "Ptr", layer.bits, "UPtr", w*h*4)
    Loop h {
        y := A_Index - 1
        dy := Min(y, h - y - 1)
        if dy < spread {
            ; For top/bottom bands, one pass per row; nearest-edge
            ; distance avoids double-opacity square patches in corners.
            Loop w {
                x := A_Index - 1
                dx := Min(x, w - x - 1)
                d := Min(dx, dy)
                if d < spread
                    NumPut "UInt", colors[d+1], layer.bits, (y*w+x)*4
            }
        } else {
            ; In the middle, paint only narrow left/right bands.
            Loop spread {
                x := A_Index - 1
                color := colors[A_Index]
                NumPut "UInt", color, layer.bits, (y*w+x)*4
                other := w - x - 1
                if other >= spread
                    NumPut "UInt", color, layer.bits, (y*w+other)*4
            }
        }
    }
}

UpdateOverlays(alpha) {
    global overlays
    for layer in overlays {
        NumPut "UChar", alpha, layer.blend, 2
        DllCall("user32\UpdateLayeredWindow", "Ptr", layer.gui.Hwnd, "Ptr", 0
            , "Ptr", layer.pos, "Ptr", layer.size, "Ptr", layer.dc, "Ptr", layer.src
            , "UInt", 0, "Ptr", layer.blend, "UInt", 2)
    }
}

Cleanup(*) {
    global overlays, gdipToken, fontFamily
    SetTimer AnimateReminder, 0
    SetTimer ReminderTimer, 0
    for layer in overlays {
        DllCall("gdi32\SelectObject", "Ptr", layer.dc, "Ptr", layer.old)
        DllCall("gdi32\DeleteObject", "Ptr", layer.bitmap)
        DllCall("gdi32\DeleteDC", "Ptr", layer.dc)
    }
    if fontFamily
        DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fontFamily)
    if gdipToken
        DllCall("gdiplus\GdiplusShutdown", "Ptr", gdipToken)
}

#HotIf reminderActive
Esc::HideReminder()
#HotIf
