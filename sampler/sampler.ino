// pins
const byte ledPin = 13;
const byte interruptPin = 2;
const byte dataPin = 3;
// timing constants
const int clock_duration = 220;
const int clock_preamble = clock_duration*2;
const int clock_preamble_tolerance = clock_preamble/10;
const int clock_idle = 6000;
volatile unsigned long now = 0;
volatile unsigned long last_clock_ts = 0;
volatile unsigned long clock_interval = 0;
// for printing
unsigned long last_print_ts = 0;
unsigned long last_print_interval = 0;
// 500 ms
const long print_interval = 500000;
// variables
volatile int bit_pos = 0;
const int word_length = 64;
volatile char data_word[word_length+1] = {0};
volatile boolean startup = true;
volatile boolean word_ready = false;

void int_clock() {
  // update timings
  now = micros();
  clock_interval = now - last_clock_ts;
  // ignore false clocks
  if (clock_interval < clock_duration/2) {
    return;
  }
  // update timings
  last_clock_ts = now;
  // check for the first clock with some tolerance
  if (clock_interval > (clock_preamble-clock_preamble_tolerance) && clock_interval < (clock_preamble+clock_preamble_tolerance)) {
    // a valid word is exactly the length of the word
    if (!startup) {
      // the previous word is valid
      detachInterrupt(0);
      word_ready = true;
      return;
    }
    bit_pos = 0;
    startup = false;
  } else if (startup) {
    return;
  }
  // allow the edge to dissipate
  delayMicroseconds(100);
  // read the data (goes low) and shift
  data_word[bit_pos++] = (char) !digitalRead(dataPin);
}

void setup() {
  Serial.begin(9600);
  pinMode(ledPin, OUTPUT);
  pinMode(interruptPin, INPUT);
  pinMode(dataPin, INPUT_PULLUP);
  // older compiler
  //attachInterrupt(digitalPinToInterrupt(interruptPin), int_clock, CHANGE);
  //Board	        int.0	int.1	int.2	int.3	int.4	int.5
  //Uno, Ethernet	2	    3
  attachInterrupt(0, int_clock, CHANGE);
}

void loop() {
  // we're outside of the data word
  if (word_ready) {
    // print heartbeat (full state)
    last_print_interval = micros() - last_print_ts;
    if (last_print_interval > print_interval) {
      digitalWrite(ledPin, HIGH);
      for (int i=0; i<word_length; i++) {
        Serial.print(data_word[i], DEC);
      }
      Serial.println();
      last_print_ts = micros();
    }
    // processing complete, attach the interrupt again
    word_ready = false;
    startup = true;
    attachInterrupt(0, int_clock, CHANGE);
  }
  // sleep so that we're not processing while an interrupt may be busy
  delayMicroseconds(clock_idle*2);
  digitalWrite(ledPin, LOW);
}
