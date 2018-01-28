{
    --------------------------------------------
    Filename:
    Author:
    Copyright (c) 20__
    See end of file for terms of use.
    --------------------------------------------
}

CON

  _clkmode  = cfg#_clkmode
  _xinfreq  = cfg#_xinfreq

  SLAVE_EE        = $50 << 1
  SLAVE_SENS      = $60 << 1
  W               = %0
  R               = %1
  EE_SIZE         = 256
  EE_CLK          = 400_000
  THERM_CLK       = 100_000
  PAGE            = 0
  SINGLE_LINE     = 1

  CMD_WRITE_CFG       = $03
  CMD_WRITE_OSC_TRIM  = $04


OBJ

  cfg   : "config.activityboard"
  ser   : "com.serial.terminal"
  time  : "time"
  i2c   : "jm_i2c_fast"
  debug : "debug"

VAR

  byte _ee_data[EE_SIZE]
  long _scl, _sda
  byte _osc_trim
  byte _ackbit
  long _nak
  long _monitor_ack_stack[100]
  word _ir_frame[64]
  word _cfg_reg
  word _comp_pix

PUB Start(SCL, SDA, I2C_HZ) | check, i, col, line, rawpix
''  TASKS:
''C  1 POR (see 8.3)
''C  2 wait 5ms
''C  3 read eeprom table
''  4 store cal coeff in prop RAM
''C  5 write osc trim val into addr $93
''C  6 write cfg val addr $92 (value read from eeprom or hard coded externally)
''C    set POR/brown out flag to 1 (bit 10 at $92
''  7 check BO flag. Cleared? Yes: repeat step 3 No: proceed to step 8
''C  8 read meas data (PTAT+desired IR data)
''  9 Ta calc
''  10 pix offset cancelling
''  11 therm grad comp
''  12 pix<->pix normalization
''  13 obj emissivity comp
''  14 obj temp calc
''  15 image process/correct
''  loop to step 7

  _scl := 8
  _sda := 7

  Setup

  repeat
'    GetColumn(0)
'    Getline (1)
'    GetPixel (3, 2)
    GetFrame
    repeat line from 0 to 3
      repeat col from 0 to 15
        ser.Hex (_ir_frame.word[((line*16)+col)], 4)
        ser.Char (" ")
      ser.NewLine
    ser.NewLine
    time.MSleep (100)


PUB Setup | check

  ser.Start (115_200)
  ser.Clear
  cognew(monitor_ack, @_monitor_ack_stack)

  i2c.setupx (_scl, _sda, EE_CLK)
  time.MSleep (3)
  i2c.start
  check := i2c.write(SLAVE_EE|W)
  i2c.stop
  if (check == i2c#ACK)
    ser.Str (string("MLX90621 EEPROM found, reading...", ser#NL))
  read_ee
  
  i2c.terminate
  i2c.setupx (_scl, _sda, THERM_CLK)

  Write_OSCTrim ($0010)'(peek_ee ($F7)) ' Write osc trimming val extracted from EEPROM address $F7
  ser.NewLine
  Write_Cfg ($4E3B) '463E
  time.MSleep (5)
  
  ser.NewLine
  Read_Cfg
  Read_OSCTrim
  ser.CharIn

{
  repeat
    Read_PTAT
    time.mSleep (100)
}
  wordfill(@_ir_frame, 0, 64)

PRI command (slave_addr, cmd_byte, st_addr, addr_step, nr_reads) | cmd_packet[2]

  cmd_packet.byte[0] := slave_addr
  cmd_packet.byte[1] := cmd_byte
  cmd_packet.byte[2] := st_addr
  cmd_packet.byte[3] := addr_step
  cmd_packet.byte[4] := nr_reads

  i2c.start
  _ackbit := i2c.pwrite(@cmd_packet, 5)

PRI readword: data_word | read_data

  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|R)
  i2c.stop
  
  i2c.pread (@read_data, 2, TRUE)
  i2c.stop

  data_word := (read_data.byte[1] << 8) | read_data.byte[0]

PUB GetCompPixel | rawpix

  command(SLAVE_SENS|W, $02, $41, $00, $01)
  
  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|R)
  i2c.stop

  i2c.pread (@rawpix, 1, TRUE)
  i2c.stop

  if rawpix > 32767  'Two's-complement
    rawpix:= rawpix - 65536
  _comp_pix := rawpix
  
PUB GetLine(line) | offs, rawpix[8], col

  offs := 16

  case line
    0..3:
      command(SLAVE_SENS|W, $02, line, $04, $10)
      
      i2c.start
      _ackbit := i2c.write (SLAVE_SENS|R)
      i2c.stop
    
      i2c.pread (@rawpix, 32, TRUE)
      i2c.stop

      repeat col from 0 to 15
        if rawpix.word[col] > 32767  'Two's-complement
          rawpix.word[col] := rawpix.word[col] - 65536

      repeat col from 0 to 15
        _ir_frame.word[(line * offs) + col] := rawpix.word[col]

    OTHER:
      return

PUB GetColumn(col) | offs, rawpix[2], line

  offs := 16

  case col
    0..15:
      command(SLAVE_SENS|W, $02, col * 4, $01, $04)
      
      i2c.start
      _ackbit := i2c.write (SLAVE_SENS|R)
      i2c.stop
    
      i2c.pread (@rawpix, 8, TRUE)
      i2c.stop

      repeat line from 0 to 3
        if rawpix.word[line] > 32767  'Two's-complement
          rawpix.word[line] := rawpix.word[line] - 65536
        _ir_frame.word[(line * offs) + col] := rawpix.word[line]

    OTHER:
      return

PUB GetPixel(col, line): pix | offs, rawpix

  offs := 16
  
  if col < 0 or col > 15 or line < 0 or line > 15
    return

  command(SLAVE_SENS|W, $02, (line * offs) + col, $01, $01)

  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|R)
  i2c.stop

  i2c.pread (@rawpix, 2, TRUE)
  i2c.stop

  if rawpix > 32767  'Two's-complement
    rawpix := rawpix - 65536

  _ir_frame.word[(line * offs) + col] := rawpix

PUB GetFrame | line, col, offs, rawpix[32], pixel

  offs := 16

  command(SLAVE_SENS|W, $02, $00, $01, $40)

  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|R)
  i2c.stop

  i2c.pread (@rawpix, 128, TRUE)
  i2c.stop

  repeat line from 0 to 3
    repeat col from 0 to 15
      pixel := (line * offs) + col
      if rawpix.word[pixel] > 32767  'Two's-complement
        rawpix.word[pixel] := rawpix.word[pixel] - 65536
      _ir_frame.word[pixel] := rawpix.word[pixel]

PUB Read_PTAT | read_data, lsbyte, msbyte, PTAT, Vth_h, Vth_l, Vth25, Kt1, Kt1_h, Kt1_l, Kt2, Kt2_h, Kt2_l, KtScl, VthExp, Scale, Ta

  Scale := 100
  msbyte := lsbyte := 0
  command(SLAVE_SENS|W, $02, $40, $00, $01)
  read_data := readword
  
  msbyte := read_data.byte[1]
  lsbyte := read_data.byte[0]
  PTAT := ((msbyte << 8) | lsbyte) * Scale
  
  ser.NewLine
  ser.NewLine
  ser.Str (string("PTAT: "))
  ser.dec (PTAT)
  ser.NewLine
''  Ta = -Kt1 + sqrt(Kt1^2-4Kt2[Vth(25)-PTAT_data]) / 2Kt2 + 25, degC
  Vth_h := _ee_data.byte[$DB] '645F
  Vth_l := _ee_data.byte[$DA]
  Kt1_h := _ee_data.byte[$DD] '545E
  Kt1_l := _ee_data.byte[$DC]
  Kt2_h := _ee_data.byte[$DF] '5EB9 
  Kt2_l := _ee_data.byte[$DE]
  KtScl := _ee_data.byte[$D2] '8B
  VthExp := 3-((_cfg_reg & %0011_0000) >> 4)

'  Vth25 := 256 * Vth_h + Vth_l  'Page 15
  Vth25 := 25632 'XXX
  if Vth25 > 32767
    Vth25 := Vth25 - 65536
  Vth25 := Vth25/pow(2, VthExp) * Scale
  ser.Str (string("Vth25 = "))
  ser.Dec (Vth25)
  ser.NewLine


'  Kt1 := 256 * Kt1_h + Kt1_l
  Kt1 := 21897 'XXX
  ser.Str (string("Kt1 = "))
  ser.Dec (Kt1)
  ser.NewLine

  if Kt1 > 32767
    Kt1 := Kt1 - 65536
  Kt1 := (Kt1)/( (pow(2, _ee_data.byte[$D2] >> 4) * pow(2, VthExp)) )*Scale 'Page 15
  Kt1 := Kt1 + (Kt1 * Scale)//( (pow(2, _ee_data.byte[$D2] >> 4) * pow(2, VthExp)) )
  ser.Str (string("Kt1(p) = "))
  ser.Dec (Kt1)
  ser.NewLine

'  Kt2 := 256 * Kt2_h + Kt2_l
  Kt2 := 24190 'XXX
  ser.Str (string("Kt2 = "))
  ser.Dec (Kt2)
  ser.NewLine

  if Kt2 > 32767
    Kt2 := Kt2 - 65536

  Kt2 := (Kt2*Scale)/( (pow(2, (_ee_data.byte[$D2] & $0F) + 10) * pow(2, VthExp)) ){*Scale} 'Page 15
'  ser.Str (string("EE [$D2] & $F = "))
'  ser.Hex (_ee_data.byte[$D2] & $f, 2)
'  ser.NewLine

  ser.Str (string("Kt2(p) = "))
  ser.Dec (Kt2)
  ser.NewLine

  ser.Dec (Ta)
  return Ta := (Kt1 * -1) + ^^(pow(Kt1, 2) - (4 * Kt2) * (Vth25 - PTAT) / (2 * Kt2) ) + 25

PUB pow(a, b) | p

  if b == 0
    return 1
  elseif b // 2 == 1
    return a * pow(a, b - 1)
  else
    p := pow(a, b / 2)
    return p * p

PUB Read_Cfg | read_data, por_bit

  command(SLAVE_SENS|W, $02, $92, $00, $01)
  read_data := readword

  _cfg_reg := (read_data.byte[1] << 8) | read_data.byte[0]
  msg_four(string("cfg: "), _cfg_reg)
  por_bit := (_cfg_reg & %0000_0100_0000_0000) >> 10        'Check if POR bit (bit 10) is set
  ser.Str (string("por bit: "))
  if por_bit
    ser.Str (string("set", ser#NL))
  else
    ser.Str (string("not set", ser#NL))

PUB Read_OSCTrim | read_data, osctrim_data

  command(SLAVE_SENS|W, $02, $93, $00, $01)
  read_data := readword
  
  osctrim_data := (read_data.byte[1] << 8) | read_data.byte[0]
  msg_four(string("osc_trim: "), osctrim_data)

PUB Write_OSCTrim(val_word) | ck, lsbyte, lsbyte_ck, msbyte, msbyte_ck

  ck := $AA
  lsbyte := val_word.byte[0]
  msbyte := val_word.byte[1]
  lsbyte_ck := (lsbyte - ck)           'Generate simple checksum values
  msbyte_ck := (msbyte - ck)           'from least and most significant bytes 
  
  msg_two(string("b: "), val_word)
  msg_one(string("lsbck: "), lsbyte_ck)
  msg_one(string("lsb: "), lsbyte)
  msg_one(string("msbck: "), msbyte_ck)
  msg_one(string("msb: "), msbyte)

  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|W)
  _ackbit := i2c.write (CMD_WRITE_OSC_TRIM)
  _ackbit := i2c.write (lsbyte_ck)
  _ackbit := i2c.write (lsbyte)
  _ackbit := i2c.write (msbyte_ck)
  _ackbit := i2c.write (msbyte)
  i2c.stop

PUB Write_Cfg(val_word) | ck, lsbyte, lsbyte_ck, msbyte, msbyte_ck
'' val_word is MSB first
  ck := $55
  lsbyte := val_word.byte[0]
  msbyte := val_word.byte[1]
  msbyte |= %0100                       'Bit 10 of the data (i.e., bit 2 of the MSB)
                                        'is the POR/Brown-Out flag, and MUST be set
                                        'to indicate the device hasn't been reset

  lsbyte_ck := (lsbyte - ck)            'Generate simple checksum values
  msbyte_ck := (msbyte - ck)            'from least and most significant bytes 
  
  msg_two(string("b: "), val_word)
  msg_one(string("lsbck: "), lsbyte_ck)
  msg_one(string("lsb: "), lsbyte)
  msg_one(string("msbck: "), msbyte_ck)
  msg_one(string("msb | %100: "), msbyte)

  i2c.start
  _ackbit := i2c.write (SLAVE_SENS|W)
  _ackbit := i2c.write (CMD_WRITE_CFG)
  _ackbit := i2c.write (lsbyte_ck)
  _ackbit := i2c.write (lsbyte)
  _ackbit := i2c.write (msbyte_ck)
  _ackbit := i2c.write (msbyte)
  i2c.stop
  
PUB dump_ee | pg, row, val

  pg := 0
  
  ser.Chars (" ", 4)
  repeat val from 0 to 15
    ser.Hex (val, 2)
    ser.Char (" ")
  ser.NewLine
  ser.NewLine
  
  repeat row from 0 to 15
    ser.Hex (row*$10, 2)
    ser.Str (string(": "))
    repeat val from 0 to 15
      ser.Hex (_ee_data.byte[pg+val], 2)
      ser.Char (" ")
    ser.NewLine
    pg+=16

PUB peek_ee(location)
'' Return byte at 'location' in EEPROM memory
  return _ee_data.byte[location]
  
PUB read_ee
'' Read EEPROM contents into RAM
  bytefill (@_ee_data, $00, EE_SIZE)  'Make sure data in RAM copy of EEPROM image is clear

  i2c.start
  _ackbit := i2c.write (SLAVE_EE|W)
  _ackbit := i2c.write ($00)

  i2c.start                           'Read in the EEPROM
  _ackbit := i2c.write (SLAVE_EE|R)
  i2c.stop
  _ackbit := i2c.pread (@_ee_data, EE_SIZE-1, TRUE)
  i2c.stop

PRI monitor_ack
'' Trialling this as a background monitor for I2C NAKs
'' - Intended to run in another cog
  repeat
    if _ackbit == i2c#NAK
      _nak++
      ser.Str (string("NAK - "))
      ser.Dec (_nak)
      _ackbit := 0
 
PRI msg_one(msg, val)
'' Writes string and one byte-sized value to terminal
  ser.Str (msg)
  ser.Hex (val, 2)
  ser.NewLine

PRI msg_two(msg, val)
'' Writes string and two byte/word-sized value to terminal
  ser.Str (msg)
  ser.Hex (val, 4)
  ser.NewLine

PRI msg_four(msg, val)
'' Writes string and four byte/long-sized value to terminal
  ser.Str (msg)
  ser.Hex (val, 8)
  ser.NewLine

  
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
