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
global lastAppliedAlpha := -1
global reminderMinutes := 20
global intervalIndex := 3
global intervalValues := [5, 10, 20, 30, 45, 60]
global intervalLabels := ["5 minutes", "10 minutes", "20 minutes", "30 minutes", "45 minutes", "60 minutes"]
global overlays := []
global menuOpen := false
global menuGui := 0
global menuPanel := 0
global uiHeight := 332
global hoverPart := ""
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
OnMessage(0x0200, HandlePointerMove)
OnMessage(0x02A3, HandlePointerLeave)

A_IconTip := "NordEye — Eye Rest Reminder"
A_TrayMenu.Delete()
A_TrayMenu.Add("Open NordEye", ShowApp)
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Open NordEye"
A_TrayMenu.ClickCount := 1

StartGraphics()
CreateOverlays()
UpdateOverlays(0)  ; Prepare fully transparent layered windows BEFORE they are shown.
main.Show("Hide w432 h332")
RoundMain()
DrawPanel()
CreateDropdown()
main.Show()
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
    global panel, intervalIndex, intervalLabels, running, hoverPart
    bitmap := 0, graphics := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 432, "Int", 332, "Int", 0
        , "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF101C2D)

    DrawWindowShell(graphics)
    EyeIcon(graphics, 29, 29, 0xFF19C8FC)
    TextAt(graphics, "NordEye", 78, 21, 240, 39, 20.5, 0xFFE9F3FF, true)
    Line(graphics, 364, 37, 374, 37, 0xFFA1B3CB, 1.6)
    Line(graphics, 395, 32, 406, 43, 0xFFA1B3CB, 1.6)
    Line(graphics, 406, 32, 395, 43, 0xFFA1B3CB, 1.6)

    DrawIconTile(graphics, 26, 103, 50, 50)
    ClockIcon(graphics, 51, 128, 0xFFCADCF5)
    TextAt(graphics, "Remind every", 93, 98, 287, 30, 14.2, 0xFFE9F3FF)
    TextAt(graphics, "Eye rest interval", 93, 126, 285, 20, 10.8, 0xFF8199B9)
    DrawControl(graphics, 93, 160, 309, 45, intervalLabels[intervalIndex], hoverPart = "interval")

    Line(graphics, 25, 233, 407, 233, 0xFF2B405B, 0.9)
    DrawAction(graphics, 23, 256, 145, 54, running ? "Running" : "Start", "primary", hoverPart = "start")
    DrawAction(graphics, 178, 256, 101, 54, "Pause", "secondary", hoverPart = "pause")
    DrawAction(graphics, 289, 256, 120, 54, "Preview", "secondary", hoverPart = "preview")

    bitmapHandle := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &bitmapHandle, "UInt", 0xFF101C2D)
    panel.Value := "HBITMAP:*" bitmapHandle
    DllCall("gdi32\DeleteObject", "Ptr", bitmapHandle)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
}


; Draw a separate non-activating popup, not a resized main window.
; Its image is prepared while hidden, avoiding an unpainted first frame.
CreateDropdown() {
    global main, menuGui, menuPanel
    menuGui := Gui("-Caption +ToolWindow -DPIScale +Owner" main.Hwnd " +E0x08000000", "Interval")
    menuGui.BackColor := "172638"
    menuGui.MarginX := 0
    menuGui.MarginY := 0
    menuPanel := menuGui.AddPicture("x0 y0 w309 h199 +0x100")
    menuPanel.OnEvent("Click", HandleMenuClick)
    menuGui.Show("Hide w309 h199")
    region := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", 310, "Int", 200, "Int", 24, "Int", 24, "Ptr")
    DllCall("user32\SetWindowRgn", "Ptr", menuGui.Hwnd, "Ptr", region, "Int", 0)
    DrawDropdown()
}

DrawDropdown() {
    global menuPanel, intervalLabels, intervalIndex
    bitmap := 0, graphics := 0, bitmapHandle := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 309, "Int", 199, "Int", 0
        , "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", graphics, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF192941)
    GradientRounded(graphics, 0.5, 0.5, 308, 198, 12, 0xFF223750, 0xFF142238, 0xFF3C6689, 1.1)
    Outline(graphics, 2, 2, 305, 195, 11, 0x2B49C9FF, 1)
    for idx, label in intervalLabels {
        rowY := 8 + (idx - 1) * 31
        if idx = intervalIndex
            GradientRounded(graphics, 7, rowY, 295, 29, 7, 0xFF2D516F, 0xFF213C59, 0xFF3F8BB6, 1)
        TextAt(graphics, label, 22, rowY, 240, 29, 13.2
            , idx = intervalIndex ? 0xFF76DDFF : 0xFFE1EEFC)
        if idx = intervalIndex
            TextAt(graphics, "✓", 271, rowY, 22, 29, 12.5, 0xFF76DDFF, true, 1)
    }
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &bitmapHandle, "UInt", 0xFF192941)
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
    menuGui.Show("NA x" (x + 93) " y" (y + 207) " w309 h199")
}

HandleMenuClick(*) {
    global menuGui, intervalIndex, intervalValues, reminderMinutes, running
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", menuGui.Hwnd, "Ptr", point)
    y := NumGet(point, 4, "Int")
    if y >= 8 && y < 194 {
        index := Floor((y - 8) / 31) + 1
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

; -------- Reference-matched GDI+ surfaces / controls --------

GradientRounded(g, x, y, w, h, r, topColor, bottomColor, border := 0, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    rect := Buffer(16, 0)
    NumPut "Float", x, rect, 0
    NumPut "Float", y, rect, 4
    NumPut "Float", w, rect, 8
    NumPut "Float", h, rect, 12
    brush := 0
    result := DllCall("gdiplus\GdipCreateLineBrushFromRect", "Ptr", rect
        , "UInt", topColor, "UInt", bottomColor, "Int", 1, "Int", 0, "Ptr*", &brush)
    if result || !brush
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", topColor, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if border
        StrokePath(g, path, border, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

DrawWindowShell(g) {
    ; An inset shadow + cold, thin rim (rather than a flat outline).
    GradientRounded(g, 0, 0, 432, 332, 18, 0xFF17283E, 0xFF0D1727)
    Outline(g, 0.8, 0.8, 430.4, 330.4, 18, 0x4D39BFFF, 2.4)
    Outline(g, 1.5, 1.5, 429, 329, 18, 0xB13FA9ED, 1.05)
    Outline(g, 3.8, 3.8, 424.4, 324.4, 16, 0x2149B7FF, 2)
    Line(g, 23, 5, 408, 5, 0x193AB9F9, 1)
}

DrawIconTile(g, x, y, w := 43, h := 43) {
    GradientRounded(g, x, y, w, h, 11, 0xFF233650, 0xFF18273D, 0xFF2C405C, 0.9)
    Outline(g, x+1.4, y+1.4, w-2.8, h-2.8, 10, 0x1935B9F4, 1)
}

DrawControl(g, x, y, w, h, label, hot := false) {
    if hot {
        Outline(g, x-3, y-3, w+6, h+6, 13, 0x1F45CFFF, 2)
        Outline(g, x-1.5, y-1.5, w+3, h+3, 12, 0x3C35CCFF, 1.5)
    }
    GradientRounded(g, x, y, w, h, 10, hot ? 0xFF263C57 : 0xFF213249
        , hot ? 0xFF1B2E47 : 0xFF18283F, hot ? 0xFF4AABEF : 0xFF395A7F, 1.2)
    Outline(g, x+1.8, y+1.8, w-3.6, h-3.6, 9, 0x2C2AAAF5, 0.85)
    TextAt(g, label, x+15, y+1, w-52, h-2, 13.6, 0xFFE7F3FF)
    ax := x + w - 25, ay := y + h/2
    Line(g, ax-6, ay-3, ax, ay+3, 0xFFB3CBE6, 1.8)
    Line(g, ax, ay+3, ax+6, ay-3, 0xFFB3CBE6, 1.8)
}

DrawAction(g, x, y, w, h, title, kind, hot := false) {
    if kind = "primary" {
        if hot {
            Outline(g, x-3, y-3, w+6, h+6, 13, 0x3435DEFF, 2.5)
            Outline(g, x-1.5, y-1.5, w+3, h+3, 12, 0x6341D8FF, 1.5)
        }
        GradientRounded(g, x, y, w, h, 11
            , hot ? 0xFF4BE3FF : 0xFF21C5FA, hot ? 0xFF06A6F4 : 0xFF079CE7, 0xFF3DE7FF, 1.25)
        Outline(g, x+1.7, y+1.7, w-3.4, h-3.4, 10, 0x7F97F4FF, 1)
        color := 0xFFFFFFFF
    } else {
        if hot
            Outline(g, x-2, y-2, w+4, h+4, 12, 0x3140C7FA, 1.8)
        GradientRounded(g, x, y, w, h, 11
            , hot ? 0xFF2A4261 : 0xFF26364F, hot ? 0xFF1C304A : 0xFF1C2B42
            , hot ? 0xFF5087BB : 0xFF344E70, 1.1)
        Outline(g, x+1.5, y+1.5, w-3, h-3, 10, 0x2535A8F4, 1)
        color := 0xFFDAE7FA
    }

    fontSize := 13.4
    iconBoxW := 26
    gap := 10
    textW := ApproxTextWidth(title, fontSize)
    contentW := iconBoxW + gap + textW
    contentLeft := x + Floor((w - contentW) / 2)
    if contentLeft < x + 12
        contentLeft := x + 12
    iconCX := contentLeft + iconBoxW / 2
    textX := contentLeft + iconBoxW + gap
    textRectW := w - (textX - x) - 12

    if title = "Start" || title = "Running" || title = "Resume" {
        if title = "Running"
            TextAt(g, "✓", iconCX - 10, y+1, 20, h-2, 16, color, true, 1)
        else
            TextAt(g, "▶", iconCX - 10, y+1, 20, h-2, 17, color, true, 1)
    } else if title = "Preview" {
        SmallEyeIcon(g, iconCX, y + h / 2, color)
    } else {
        Rounded(g, iconCX - 6, y+h/2-9, 4, 18, 2, color)
        Rounded(g, iconCX + 3, y+h/2-9, 4, 18, 2, color)
    }
    TextAt(g, title, textX, y+1, textRectW, h-2, fontSize, color)
}

ApproxTextWidth(text, size) {
    return Ceil(StrLen(text) * size * 0.58)
}

SmallEyeIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 2.2, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen
        , "Float", x-12, "Float", y, "Float", x-6, "Float", y-9
        , "Float", x+6, "Float", y-9, "Float", x+12, "Float", y)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen
        , "Float", x-12, "Float", y, "Float", x-6, "Float", y+9
        , "Float", x+6, "Float", y+9, "Float", x+12, "Float", y)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen
        , "Float", x-3.5, "Float", y-3.5, "Float", 7, "Float", 7)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

TrackPointerLeave(hwnd) {
    event := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut "UInt", event.Size, event, 0
    NumPut "UInt", 2, event, 4 ; TME_LEAVE
    NumPut "Ptr", hwnd, event, 8
    DllCall("user32\TrackMouseEvent", "Ptr", event)
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

; Filled, antialiased eye mark matching the NordEye visual reference.
; All geometry is vector GDI+: no icon fonts or external assets required.
EyeIcon(g, x, y, color) {
    eyePath := 0, brush := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &eyePath)
    ; Almond-shaped outer silhouette (42 x 23 px).
    DllCall("gdiplus\GdipAddPathBezier", "Ptr", eyePath
        , "Float", x, "Float", y+10.5
        , "Float", x+10, "Float", y-2
        , "Float", x+31, "Float", y-2
        , "Float", x+42, "Float", y+10.5)
    DllCall("gdiplus\GdipAddPathBezier", "Ptr", eyePath
        , "Float", x+42, "Float", y+10.5
        , "Float", x+31, "Float", y+23
        , "Float", x+10, "Float", y+23
        , "Float", x, "Float", y+10.5)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", eyePath)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", eyePath)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    DllCall("gdiplus\GdipDeletePath", "Ptr", eyePath)

    ; Deep navy iris, vibrant inner pupil and small highlight.
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF10263E, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", brush
        , "Float", x+12.5, "Float", y+1, "Float", 17, "Float", 19)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFF27D4FF, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillEllipse", "Ptr", g, "Ptr", brush
        , "Float", x+18, "Float", y+7, "Float", 6.5, "Float", 7)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
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

HoverAt(x, y) {
    if x >= 93 && x <= 402 && y >= 160 && y <= 205
        return "interval"
    if y >= 256 && y <= 310 {
        if x >= 23 && x <= 168
            return "start"
        if x >= 178 && x <= 279
            return "pause"
        if x >= 289 && x <= 409
            return "preview"
    }
    return ""
}

HandlePointerMove(wParam, lParam, msg, hwnd) {
    global main, hoverPart
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != main.Hwnd
        return
    TrackPointerLeave(hwnd)
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", main.Hwnd, "Ptr", point)
    hovered := HoverAt(NumGet(point, 0, "Int"), NumGet(point, 4, "Int"))
    if hovered != hoverPart {
        hoverPart := hovered
        DrawPanel()
    }
}

HandlePointerLeave(wParam, lParam, msg, hwnd) {
    global main, hoverPart
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = main.Hwnd && hoverPart != "" {
        hoverPart := ""
        DrawPanel()
    }
}

HandlePanelClick(*) {
    global main, menuOpen
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", main.Hwnd, "Ptr", point)
    x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    if y < 58 && x >= 385 {
        CloseApp()
        return
    }
    if y < 58 && x >= 349 {
        CloseMenu()
        main.Minimize()
        return
    }
    if menuOpen {
        CloseMenu()
        return
    }
    if x >= 93 && x <= 402 && y >= 160 && y <= 205
        OpenMenu()
    else if y >= 256 && y <= 310 {
        if x >= 23 && x <= 168
            StartReminder()
        else if x >= 178 && x <= 279
            PauseReminder()
        else if x >= 289 && x <= 409
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
    displayAlpha := 0
    ; The cached ARGB surface has already been uploaded with alpha=0 at startup.
    ; Never show an uninitialized layered window: it may flash for one frame.
    UpdateOverlays(0)
    for layer in overlays
        layer.gui.Show("NA")
    animationStart := A_TickCount
    SetTimer AnimateReminder, 16
}

HideReminder(*) {
    global reminderActive, animationMode, animationStart, animationFromAlpha, displayAlpha
    if !reminderActive || animationMode = 2
        return
    animationMode := 2
    animationStart := A_TickCount
    animationFromAlpha := displayAlpha
    SetTimer AnimateReminder, 16
}

AnimateReminder(*) {
    global animationMode, animationStart, animationFromAlpha, displayAlpha, reminderActive, overlays
    elapsed := A_TickCount - animationStart
    switch animationMode {
        case 1:
            ; 1.2-second smoothstep: zero velocity at both ends, not a fast flash.
            portion := Min(1, elapsed / 1200)
            ease := portion * portion * (3 - 2 * portion)
            displayAlpha := Round(255 * ease)
            if portion = 1 {
                animationMode := 3
                animationStart := A_TickCount
                ; Pulse begins at its brightest point with zero velocity,
                ; exactly where the fade-in ends. No 255 -> 214 jump.
            }
        case 2:
            portion := Min(1, elapsed / 800)
            ease := portion * portion * (3 - 2 * portion)
            displayAlpha := Round(animationFromAlpha * (1 - ease))
            if portion = 1 {
                displayAlpha := 0
                UpdateOverlays(0)
                for layer in overlays
                    layer.gui.Hide()
                reminderActive := false
                animationMode := 0
                SetTimer AnimateReminder, 0
                return
            }
        case 3:
            phase := Mod(elapsed, 3400) / 3400
            displayAlpha := Round(173 + 82 * (0.5 + 0.5 * Cos(6.283185307179586 * phase)))
        default:
            return
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
    global overlays, lastAppliedAlpha
    ; Avoid pushing full monitor-sized bitmaps on frames with unchanged opacity.
    if alpha = lastAppliedAlpha
        return
    for layer in overlays {
        NumPut "UChar", alpha, layer.blend, 2
        DllCall("user32\UpdateLayeredWindow", "Ptr", layer.gui.Hwnd, "Ptr", 0
            , "Ptr", layer.pos, "Ptr", layer.size, "Ptr", layer.dc, "Ptr", layer.src
            , "UInt", 0, "Ptr", layer.blend, "UInt", 2)
    }
    lastAppliedAlpha := alpha
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
    if fontFamily {
        DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fontFamily)
        fontFamily := 0
    }
    ; GDI+ is process-scoped here. Avoid GdiplusShutdown during OnExit:
    ; it raises 0xC0000005 in the compiled programs on exit.
    ; Windows reclaims the GDI+ runtime when the process terminates.
    gdipToken := 0
}

#HotIf reminderActive
Esc::HideReminder()
#HotIf
