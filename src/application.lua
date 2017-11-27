local sensors = require("sensors")
local actuators = require("actuators")
local smartthings = require("smartthings")
local sensorSend = {}
local dni = wifi.sta.getmac():gsub("%:", "")
local timeout = tmr.create()
local sensorTimer = tmr.create()
local sendTimer = tmr.create()

--scl
-- HC4067 address pins
local s0 = 1
local s1 = 2
local s2 = 5
local s3 = 6
-- bank 0 enable
local ena0 = 3
-- bank 1 enable
local ena1 = 6
-- adc threshold
local adcthresh = 300

timeout:register(10000, tmr.ALARM_SEMI, node.restart)

--scl
function readHC4067Pin(pin)
  local state;

--enable is active low
  if (pin/16 == 0) then
    gpio.write(ena1,gpio.HIGH);
    gpio.write(ena0,gpio.LOW);
  else
    gpio.write(ena0,gpio.HIGH);
    gpio.write(ena1,gpio.LOW);
  end

  if (bit.band(pin,1)==1) then o=gpio.HIGH else o=gpio.LOW end
  gpio.write(s0,o)
  if (bit.band(pin,2)==2) then o=gpio.HIGH else o=gpio.LOW end
  gpio.write(s1,o)
  if (bit.band(pin,4)==4) then o=gpio.HIGH else o=gpio.LOW end
  gpio.write(s2,o)
  if (bit.band(pin,8)==8) then o=gpio.HIGH else o=gpio.LOW end
  gpio.write(s3,o)
  state = adc.read(0)
  if (state < adcthresh) then state=0 else state=1 end
  return state;
end  

print("Heap:", node.heap(), "Initializing sensor pins...")
gpio.mode(s0,gpio.OUTPUT)
gpio.mode(s1,gpio.OUTPUT)
gpio.mode(s2,gpio.OUTPUT)
gpio.mode(s3,gpio.OUTPUT)	
gpio.mode(ena0,gpio.OUTPUT)	
gpio.mode(ena1,gpio.OUTPUT)	
print("Heap:", node.heap(), "Initializing sensor pins done.")
--scl 

for i, actuator in pairs(actuators) do
  print("Heap:", node.heap(), "Initializing actuator pin:", actuator.pin, "Trigger:", actuator.trigger)
  gpio.mode(actuator.pin, gpio.OUTPUT)
  gpio.write(actuator.pin, actuator.trigger == gpio.LOW and gpio.HIGH or gpio.LOW)
end

sensorTimer:alarm(200, tmr.ALARM_AUTO, function(t)
  for i, sensor in pairs(sensors) do
    local state = readHC4067Pin(sensor.pin)
    if sensor.state ~= state then
      sensor.state = state
      table.insert(sensorSend, i)
    end
  end
end)

sendTimer:alarm(200, tmr.ALARM_AUTO, function(t)
  if sensorSend[1] then
    t:stop()
    local sensor = sensors[sensorSend[1]]
    timeout:start()
    http.put(
      table.concat({ smartthings.apiUrl, "/device/", dni, "/", sensor.pin, "/", readHC4067Pin(sensor.pin) }),
      table.concat({ "Authorization: Bearer ", smartthings.token, "\r\n" }),
      "",
      function(code)
        timeout:stop()
        print("Heap:", node.heap(), "HTTP Call:", code, "Pin:", sensor.pin, "State:", readHC4067Pin(sensor.pin))
        table.remove(sensorSend, 1)
        blinktimer:start()
        t:start()
      end)
    collectgarbage()
  end
end)
