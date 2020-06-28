 {
    --------------------------------------------
    Filename: MLX90621-VGA-Demo.spin
    Author: Jesse Burt
    Description: Demo of the MLX90621 driver using
        a VGA display
    Copyright (c) 2020
    Started: Jun 27, 2020
    Updated: Jun 28, 2020
    See end of file for terms of use.
    --------------------------------------------
}

CON

    _clkmode    = cfg#_clkmode
    _xinfreq    = cfg#_xinfreq

' -- User-modifiable constants
    LED             = cfg#LED1
    SER_RX          = cfg#SER_RX_DEF
    SER_TX          = cfg#SER_TX_DEF
    SER_BAUD        = cfg#SER_BAUD_DEF

    RES_PIN         = 36
    DC_PIN          = 35
    CS_PIN          = 34
    CLK_PIN         = 33
    DIN_PIN         = 32
    SCK_HZ          = 20_000_000

    I2C_SCL         = 0
    I2C_SDA         = 1
    I2C_HZ          = 1_000_000

    VGA_PINGROUP    = 2
' --

    WIDTH           = 160
    HEIGHT          = 120
    XMAX            = WIDTH-1
    YMAX            = HEIGHT-1
    CENTERX         = XMAX/2
    CENTERY         = YMAX/2
    BUFFSZ          = WIDTH * HEIGHT
    BPP             = 1
    BPL             = WIDTH * BPP

OBJ

    cfg     : "core.con.boardcfg.quickstart-hib"
    ser     : "com.serial.terminal.ansi"
    time    : "time"
    io      : "io"
    mlx     : "sensor.thermal-array.mlx90621.i2c"
    vga     : "display.vga.bitmap.160x120"
    fnt     : "font.5x8"
    int     : "string.integer"

VAR

    long _keyinput_stack[50]
    byte _palette[64]
    long _ir_frame[66]
    long _offset
    long _settings_changed

    word _mlx_refrate

    word _fx, _fy, _fw, _fh

    byte _framebuffer[BUFFSZ]
    byte _mlx_adcres, _mlx_adcref
    byte _invert_x, _col_scl
    byte _hotspot_mark

PUB Main

    setup
    drawvscale(XMAX-5, 0, YMAX)

    repeat
        if _settings_changed
            updatesettings
        mlx.getframe (@_ir_frame)
        drawframe(_fx, _fy, _fw, _fh)

PUB DrawFrame(fx, fy, pixw, pixh) | x, y, color_c, ir_offset, pixsx, pixsy, pixex, pixey, maxx, maxy, maxp
' Draw the thermal image
'    vga.waitvsync
    repeat y from 0 to mlx#YMAX
        repeat x from 0 to mlx#XMAX
            if _invert_x                                    ' Invert X display if set
                ir_offset := ((mlx#XMAX-x) * 4) + y
            else
                ir_offset := (x * 4) + y

            color_c := (_ir_frame[ir_offset] * _col_scl) / 1024 + _offset
            pixsx := fx + (x * pixw)
            pixsy := fy + (y * (pixh + 1))
            pixex := pixsx + pixw
            pixey := pixsy + pixh
            if _ir_frame[ir_offset] > maxp             ' Check if this is the hottest spot
                maxp := _ir_frame[ir_offset]
                maxx := pixsx
                maxy := pixsy
            vga.box(pixsx, pixsy, pixex, pixey, color_c, TRUE)

    if _hotspot_mark                                        ' Mark hotspot
'        vga.box(maxx, maxy, maxx+pixw, maxy+pixh, vga#MAX_COLOR, false)          ' White box
        vga.line(maxx, maxy+(pixh/2), maxx+pixw, maxy+(pixh/2), vga#MAX_COLOR)    '  - or cross-hair
        vga.line(maxx+(pixw/2), maxy, maxx+(pixw/2), maxy+pixh, vga#MAX_COLOR)    ' /

PUB DrawVScale(x, y, ht) | idx, color, scl_width, bottom, top, range                                     ' Draw the color scale setup at program start
    range := bottom := y+ht
    top := y
    scl_width := 5

    repeat idx from bottom to top
        color := (range-idx)
        vga.line(x, idx, x+scl_width, idx, color)

PUB DumpFrame | x, y, ir_offset
' Dump raw frame data to terminal
    repeat y from 0 to mlx#YMAX
        repeat x from 0 to mlx#XMAX
            if _invert_x                                    ' Invert X display if set
                ir_offset := ((mlx#XMAX-x) * 4) + y
            else
                ir_offset := (x * 4) + y
            ser.position (1+(x * 9), 9+y)                   ' Accommodate spacing for hex words
            ser.hex (_ir_frame[ir_offset], 8)
            ser.char (" ")

PUB UpdateSettings | col, row, reftmp
' Settings have been changed by the user - update the sensor and the displayed settings
    mlx.adcres (_mlx_adcres)                                ' Update sensor with current settings
    mlx.refreshrate (_mlx_refrate)
    mlx.adcreference (_mlx_adcref)

    reftmp := mlx.adcreference(-2)                          ' Re-read from sensor for display below
    col := 0
    row := (vga.textrows-1) - 4                             ' Position settings at screen bottom
    vga.fgcolor(vga#MAX_COLOR)
    vga.position(col, row)
    vga.printf(string("X-axis invert: %s\n"), lookupz(_invert_x: string("No "), string("Yes")), 0, 0, 0, 0, 0)
    vga.printf(string("FPS: %dHz   \n"), mlx.refreshrate(-2), 0, 0, 0, 0, 0)
    vga.printf(string("ADC: %dbits\n"), mlx.adcres(-2), 0, 0, 0, 0, 0)
    vga.printf(string("ADC reference: %s\n"), lookupz(reftmp: string("High"), string("Low  ")), 0, 0, 0, 0, 0)

    _fx := CENTERX - ((_fw * 16) / 2)                       ' Approx center of screen
    _fy := 10
    vga.box(0, 0, XMAX-10, CENTERY, 0, TRUE)                    ' Clear out the existing thermal image (in case resizing smaller)
    _settings_changed := FALSE

PUB cog_keyInput | cmd

    repeat
        repeat until cmd := ser.charin
        case cmd
            "A":                                            ' ADC resolution (bits)
                _mlx_adcres := (_mlx_adcres + 1) <# 18
            "a":
                _mlx_adcres := (_mlx_adcres - 1) #> 15

            "C":                                            ' Color scaling/contrast
                _col_scl := (_col_scl + 1) <# 16
            "c":
                _col_scl := (_col_scl - 1) #> 1

            "F":
                _mlx_refrate := (_mlx_refrate * 2) <# 512   ' Sensor refresh rate (Hz)
            "f":
                _mlx_refrate := (_mlx_refrate / 2) #> 1

            "h":                                            ' Mark hotspot
                _hotspot_mark ^= 1

            "r":                                            ' Sensor ADC reference (hi/low)
                _mlx_adcref ^= 1

            "S":                                            ' Thermal image pixel size
                _fw := (_fw + 1) <# 9
                _fh := (_fh + 1) <# 9
            "s":
                _fw := (_fw - 1) #> 1
                _fh := (_fh - 1) #> 1

            "-":                                            ' Thermal image reference level/color offset
                _offset := 0 #> (_offset - 1)
            "=":
                _offset := (_offset + 1) <# vga#MAX_COLOR

            "t":                                            ' Dump raw frame data to terminal
                dumpframe

            "x":                                            ' Invert thermal image display X-axis
                _invert_x ^= 1

            OTHER:
                next
        _settings_changed := TRUE                           ' Trigger for main loop to call UpdateSettings

PUB Setup

    repeat until ser.startrxtx (SER_RX, SER_TX, 0, SER_BAUD)
    time.msleep(30)
    ser.clear
    ser.str(string("Serial terminal started", ser#CR, ser#LF))

    if vga.start(VGA_PINGROUP, WIDTH, HEIGHT, @_framebuffer)
        ser.str(string("VGA 8bpp driver started", ser#CR, ser#LF))
        vga.fontaddress(fnt.BaseAddr)
        vga.fontsize(6, 8)
        vga.clear
    else
        ser.str(string("VGA 8bpp driver failed to start", ser#CR, ser#LF))
        repeat

    if mlx.start (I2C_SCL, I2C_SDA, I2C_HZ)
        ser.str(string("MLX90621 driver started", ser#CR, ser#LF))
        mlx.defaults
        mlx.opmode(mlx#CONTINUOUS)
        _mlx_adcres := 18                                   ' Initial sensor settings
        _mlx_refrate := 32
        _mlx_adcref := 1
    else
        ser.str(string("MLX90621 driver failed to start - halting", ser#CR, ser#LF))
        time.msleep (5)
        vga.stop
        mlx.stop
        repeat

    _col_scl := 16
    _fw := 6
    _fh := 6
    _invert_x := 0
    cognew(cog_keyinput, @_keyinput_stack)
    _settings_changed := TRUE

#include "lib.utility.spin"

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}