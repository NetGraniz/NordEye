#Requires AutoHotkey v2.0
#SingleInstance Force

global running := false
global reminderActive := false
global animationMode := 0
global animationStart := 0
global animationFromAlpha := 0
global displayAlpha := 0
global reminderMinutes := 20
global intervalIndex := 3
global intervalValues := [5, 10, 20, 30, 45, 60]
global intervalLabels := ["5 minutes", "10 minutes", "20 minutes", "30 minutes", "45 minutes", "60 minutes"]
global pulsePhase := 0
global overlays := []
global dropdownGui := 0
global buttonStyles := Map()
global buttonLabels := Map()

global main := Gui("+AlwaysOnTop -Caption -Resize", "NordEye")
main.BackColor := "17191E"
main.MarginX := 0
main.MarginY := 0

A_IconTip := "NordEye"
A_TrayMenu.Delete()
A_TrayMenu.Add("Open NordEye", ShowApp)
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", ExitApplication)
A_TrayMenu.Default := "Open NordEye"
A_TrayMenu.ClickCount := 1

AddLabel(main, "x22 y16 w32 h30 Center", "◆", "s11 c7DA2F8 w600")
AddLabel(main, "x58 y17 w160 h28", "NordEye", "s13 cF2F4F7 w600")
global minimizeButton := AddLabel(main, "x411 y15 w30 h28 Center", "–", "s12 c8B93A1")
global closeButton := AddLabel(main, "x450 y15 w28 h28 Center", "×", "s12 c8B93A1")
minimizeButton.OnEvent("Click", MinimizeApp)
closeButton.OnEvent("Click", CloseApp)

global clockTile := AddLabel(main, "x30 y69 w40 h40 Center Background252A33", "◷", "s13 c9AA6B8")
AddLabel(main, "x88 y69 w160 h22", "Interval", "s10 cD7DCE5 w600")
AddLabel(main, "x88 y91 w160 h19", "Remind me every", "s8 c8B93A1")

global intervalBox := main.AddText("x88 y119 w362 h40 Background252A33")
global intervalText := AddLabel(main, "x102 y119 w285 h40 BackgroundTrans", "20 minutes", "s9 cF2F4F7")
global intervalArrow := AddLabel(main, "x414 y119 w22 h40 Center BackgroundTrans", "▾", "s9 c9AA6B8")
intervalBox.OnEvent("Click", ShowIntervalMenu)
intervalText.OnEvent("Click", ShowIntervalMenu)
intervalArrow.OnEvent("Click", ShowIntervalMenu)

main.AddText("x22 y178 w456 h1 Background303640")

global startButton := main.AddPicture("x22 y198 w154 h44 +0x100")
global pauseButton := main.AddPicture("x187 y198 w132 h44 +0x100")
global previewButton := main.AddPicture("x330 y198 w148 h44 +0x100")
buttonStyles[startButton.Hwnd] := {background: 0xDB6F37, foreground: 0xFFFFFF, weight: 600}
buttonStyles[pauseButton.Hwnd] := {background: 0x332A25, foreground: 0xE5DCD7, weight: 400}
buttonStyles[previewButton.Hwnd] := {background: 0x332A25, foreground: 0xE5DCD7, weight: 400}
buttonLabels[startButton.Hwnd] := "▶   Start"
buttonLabels[pauseButton.Hwnd] := "Ⅱ   Pause"
buttonLabels[previewButton.Hwnd] := "◉   Preview"

startButton.OnEvent("Click", StartReminder)
pauseButton.OnEvent("Click", PauseReminder)
previewButton.OnEvent("Click", PreviewReminder)
main.OnEvent("Close", CloseApp)
main.OnEvent("Size", HandleSize)
OnMessage(0x0201, BeginDrag)
OnMessage(0x0003, HandleWindowMove)
OnMessage(0x0006, HandleActivate)
OnExit DisposeOverlays

CreateOverlay()
main.Show("w500 h260")
ApplyWindowVisuals()
WinRedraw "ahk_id " main.Hwnd
WinActivate "ahk_id " main.Hwnd

AddLabel(gui, options, text, fontOptions) {
    gui.SetFont(fontOptions, "Segoe UI")
    return gui.AddText(options " +0x200", text)
}

ApplyRounding() {
    global clockTile, intervalBox
    RoundControl(clockTile, 10)
    RoundControl(intervalBox, 10)
}

RoundControl(control, radius) {
    control.GetPos(, , &width, &height)
    WinSetRegion("0-0 W" width " H" height " R" (radius * 2) "-" (radius * 2), "ahk_id " control.Hwnd)
}

RenderButtons() {
    global buttonStyles
    for hwnd, style in buttonStyles
        RenderButton(GuiCtrlFromHwnd(hwnd), style)
}

RenderButton(button, style) {
    global main, buttonLabels, intervalText
    rect := Buffer(16, 0)
    DllCall("User32\GetClientRect", "Ptr", button.Hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int")
    height := NumGet(rect, 12, "Int")
    windowDC := DllCall("User32\GetDC", "Ptr", main.Hwnd, "Ptr")
    memoryDC := DllCall("Gdi32\CreateCompatibleDC", "Ptr", windowDC, "Ptr")
    bitmap := DllCall("Gdi32\CreateCompatibleBitmap", "Ptr", windowDC, "Int", width, "Int", height, "Ptr")
    oldBitmap := DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")

    backgroundBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", 0x1E1917, "Ptr")
    DllCall("User32\FillRect", "Ptr", memoryDC, "Ptr", rect, "Ptr", backgroundBrush)
    DllCall("Gdi32\DeleteObject", "Ptr", backgroundBrush)

    buttonBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", style.background, "Ptr")
    oldBrush := DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", buttonBrush, "Ptr")
    nullPen := DllCall("Gdi32\GetStockObject", "Int", 8, "Ptr")
    oldPen := DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", nullPen, "Ptr")
    dpi := DllCall("User32\GetDpiForWindow", "Ptr", main.Hwnd, "UInt")
    diameter := Round(24 * (dpi ? dpi : 96) / 96)
    DllCall("Gdi32\RoundRect", "Ptr", memoryDC, "Int", 0, "Int", 0, "Int", width, "Int", height, "Int", diameter, "Int", diameter)

    font := DllCall("User32\SendMessageW", "Ptr", intervalText.Hwnd, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")
    oldFont := DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", font, "Ptr")
    DllCall("Gdi32\SetBkMode", "Ptr", memoryDC, "Int", 1)
    DllCall("Gdi32\SetTextColor", "Ptr", memoryDC, "UInt", style.foreground)
    DllCall("User32\DrawTextW", "Ptr", memoryDC, "Str", buttonLabels[button.Hwnd], "Int", -1, "Ptr", rect, "UInt", 0x825)

    DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldFont)
    DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldPen)
    DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldBrush)
    DllCall("Gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldBitmap)
    button.Value := "HBITMAP:*" bitmap
    DllCall("Gdi32\DeleteObject", "Ptr", buttonBrush)
    DllCall("Gdi32\DeleteObject", "Ptr", bitmap)
    DllCall("Gdi32\DeleteDC", "Ptr", memoryDC)
    DllCall("User32\ReleaseDC", "Ptr", main.Hwnd, "Ptr", windowDC)
}

SetButtonLabel(button, label) {
    global buttonLabels
    buttonLabels[button.Hwnd] := label
    RenderButtons()
}

RoundWindow(hwnd, radius) {
    rect := Buffer(16, 0)
    if !DllCall("User32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        return
    width := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    dpi := DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt")
    radius := Round(radius * (dpi ? dpi : 96) / 96)
    region := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", width + 1, "Int", height + 1, "Int", radius * 2, "Int", radius * 2, "Ptr")
    DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int", true)
}

ApplyWindowVisuals(*) {
    global main
    RoundWindow(main.Hwnd, 14)
    ApplyRounding()
    RenderButtons()
    SetDarkWindow(main.Hwnd)
}

HandleSize(guiObj, minMax, width, height) {
    if minMax != -1
        ApplyWindowVisuals()
}

HandleActivate(wParam, lParam, msg, hwnd) {
    global main
    if hwnd = main.Hwnd && (wParam & 0xFFFF)
        ApplyWindowVisuals()
}

SetDarkWindow(hwnd) {
    dark := 1
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", dark, "UInt", 4)
    corner := 3
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", corner, "UInt", 4)
    borderColor := 0xFFFFFFFE
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", borderColor, "UInt", 4)
}

BeginDrag(wParam, lParam, msg, hwnd) {
    global main
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if root != main.Hwnd
        return
    MouseGetPos &mouseX, &mouseY
    WinGetPos &windowX, &windowY,,, "ahk_id " main.Hwnd
    if mouseY - windowY < 58 {
        CloseDropdown()
        PostMessage 0x00A1, 2,,, "ahk_id " main.Hwnd
    }
}

HandleWindowMove(wParam, lParam, msg, hwnd) {
    global main, dropdownGui
    if hwnd = main.Hwnd && IsObject(dropdownGui)
        CloseDropdown()
}

MinimizeApp(*) {
    global main
    CloseDropdown()
    main.Minimize()
}

CloseApp(*) {
    global main
    CloseDropdown()
    main.Hide()
}

ShowApp(*) {
    global main
    CloseDropdown()
    main.Show("Restore")
    ApplyWindowVisuals()
    WinActivate "ahk_id " main.Hwnd
}

ExitApplication(*) {
    ExitApp()
}

ShowIntervalMenu(*) {
    global main, intervalBox, intervalLabels, intervalIndex, dropdownGui
    CloseDropdown()
    intervalBox.GetPos(&controlX, &controlY, &controlW, &controlH)
    WinGetPos(&windowX, &windowY,,, "ahk_id " main.Hwnd)
    menuWidth := controlW
    menuHeight := intervalLabels.Length * 29 + 8
    dropdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner" main.Hwnd, "")
    dropdownGui.BackColor := "1F232A"
    dropdownGui.MarginX := 4
    dropdownGui.MarginY := 4
    for index, label in intervalLabels {
        color := index = intervalIndex ? "343B48" : "252A33"
        option := AddLabel(dropdownGui, "x4 y" (4 + (index - 1) * 29) " w" (menuWidth - 8) " h25 Center Background" color, label, "s9 cF2F4F7")
        option.OnEvent("Click", SelectInterval.Bind(index))
    }
    dropdownGui.Show("NA x" (windowX + controlX) " y" (windowY + controlY + controlH - 1) " w" menuWidth " h" menuHeight)
    RoundWindow(dropdownGui.Hwnd, 10)
    SetDarkWindow(dropdownGui.Hwnd)
    for control in dropdownGui
        RoundControl(control, 6)
}

SelectInterval(index, *) {
    global intervalIndex, intervalValues, intervalLabels, reminderMinutes, intervalText, running
    intervalIndex := index
    reminderMinutes := intervalValues[index]
    intervalText.Text := intervalLabels[index]
    if running
        SetTimer ReminderTimer, reminderMinutes * 60000
    CloseDropdown()
}

CloseDropdown(*) {
    global dropdownGui
    if IsObject(dropdownGui) {
        try dropdownGui.Destroy()
        dropdownGui := 0
    }
}

StartReminder(*) {
    global running, reminderMinutes, intervalValues, intervalIndex
    global startButton
    CloseDropdown()
    reminderMinutes := intervalValues[intervalIndex]
    running := true
    HideReminder()
    SetTimer ReminderTimer, reminderMinutes * 60000
    SetButtonLabel(startButton, "✓   Running")
}

PauseReminder(*) {
    global running, startButton
    CloseDropdown()
    running := false
    SetTimer ReminderTimer, 0
    HideReminder()
    SetButtonLabel(startButton, "▶   Start")
}

PreviewReminder(*) {
    CloseDropdown()
    ShowReminder()
}

ReminderTimer(*) {
    global running, reminderActive
    if running && !reminderActive
        ShowReminder()
}

CreateOverlay() {
    global overlays
    monitorCount := MonitorGetCount()
    Loop monitorCount {
        monitor := A_Index
        MonitorGet monitor, &left, &top, &right, &bottom
        width := right - left
        height := bottom - top
        edge := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x08000000 +E0x80000")
        edge.Show("Hide x" left " y" top " w" width " h" height)
        bitmapInfo := Buffer(40, 0)
        NumPut "UInt", 40, bitmapInfo, 0
        NumPut "Int", width, bitmapInfo, 4
        NumPut "Int", -height, bitmapInfo, 8
        NumPut "UShort", 1, bitmapInfo, 12
        NumPut "UShort", 32, bitmapInfo, 14
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        bits := 0
        bitmap := DllCall("CreateDIBSection", "Ptr", dc, "Ptr", bitmapInfo, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
        oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        context := {gui: edge, dc: dc, bitmap: bitmap, oldBitmap: oldBitmap, bits: bits, width: width, height: height, left: left, top: top, size: Buffer(8, 0), point: Buffer(8, 0), source: Buffer(8, 0), blend: Buffer(4, 0)}
        BuildGradient context
        NumPut "Int", width, context.size, 0
        NumPut "Int", height, context.size, 4
        NumPut "Int", left, context.point, 0
        NumPut "Int", top, context.point, 4
        NumPut "UChar", 0, context.blend, 0
        NumPut "UChar", 0, context.blend, 1
        NumPut "UChar", 255, context.blend, 2
        NumPut "UChar", 1, context.blend, 3
        overlays.Push context
    }
}

BuildGradient(context) {
    width := context.width
    height := context.height
    glowWidth := 88
    maxAlpha := 205
    DllCall "RtlZeroMemory", "Ptr", context.bits, "Ptr", width * height * 4
    Loop height {
        y := A_Index - 1
        Loop width {
            x := A_Index - 1
            distance := Min(x, y, width - 1 - x, height - 1 - y)
            if distance >= glowWidth
                continue
            edgeRatio := 1 - distance / glowWidth
            alpha := Round(maxAlpha * edgeRatio ** 1.72)
            innerRatio := distance / glowWidth
            red := Round((28 - 18 * innerRatio) * alpha / 255)
            green := Round((197 - 75 * innerRatio) * alpha / 255)
            blue := Round((255 - 15 * innerRatio) * alpha / 255)
            pixel := blue | (green << 8) | (red << 16) | (alpha << 24)
            NumPut "UInt", pixel, context.bits, (y * width + x) * 4
        }
    }
}

ShowReminder(*) {
    global reminderActive, animationMode, animationStart, displayAlpha, pulsePhase, overlays
    if reminderActive || animationMode != 0
        return
    reminderActive := true
    animationMode := 1
    animationStart := A_TickCount
    displayAlpha := 0
    pulsePhase := 0
    for context in overlays
        context.gui.Show "NA"
    UpdateOverlay 0
    SetTimer AnimateReminder, 20
}

HideReminder(*) {
    global reminderActive, animationMode, animationStart, animationFromAlpha, displayAlpha
    if !reminderActive
        return
    animationMode := 2
    animationStart := A_TickCount
    animationFromAlpha := displayAlpha
    SetTimer AnimateReminder, 20
}

AnimateReminder(*) {
    global reminderActive, animationMode, animationStart, animationFromAlpha, displayAlpha, pulsePhase, overlays
    elapsed := A_TickCount - animationStart
    if animationMode = 1 {
        displayAlpha := Min(255, Round(255 * elapsed / 500))
        if elapsed >= 500 {
            animationMode := 3
            animationStart := A_TickCount
            pulsePhase := 0
        }
    } else if animationMode = 2 {
        displayAlpha := Max(0, Round(animationFromAlpha * (1 - elapsed / 600)))
        if elapsed >= 600 {
            displayAlpha := 0
            reminderActive := false
            animationMode := 0
            for context in overlays
                context.gui.Hide()
            SetTimer AnimateReminder, 0
        }
    } else if animationMode = 3 {
        pulsePhase := Mod(A_TickCount - animationStart, 3000) / 3000
        displayAlpha := Round(185 + 45 * (0.5 + 0.5 * Sin(2 * 3.14159265358979 * pulsePhase)))
    }
    UpdateOverlay displayAlpha
}

UpdateOverlay(alpha) {
    global overlays
    for context in overlays {
        NumPut "UChar", alpha, context.blend, 2
        DllCall "UpdateLayeredWindow", "Ptr", context.gui.Hwnd, "Ptr", 0, "Ptr", context.point, "Ptr", context.size, "Ptr", context.dc, "Ptr", context.source, "UInt", 0, "Ptr", context.blend, "UInt", 2
    }
}

DisposeOverlays(*) {
    global overlays
    CloseDropdown()
    for context in overlays {
        DllCall "SelectObject", "Ptr", context.dc, "Ptr", context.oldBitmap
        DllCall "DeleteObject", "Ptr", context.bitmap
        DllCall "DeleteDC", "Ptr", context.dc
    }
}

#HotIf reminderActive
Esc::HideReminder()
#HotIf
