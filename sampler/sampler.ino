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
volatile unsigned long last_clock = 0;
volatile unsigned long clock_interval = 0;
// for printing
unsigned long last_print = 0;
unsigned long print_interval = 0;
//const long print_frequency = 10000000;
const long print_frequency = 1000000;
// variables
volatile int bit_pos = 0;
const int word_length = 64;
volatile char data_word[word_length+1] = {0};
char previous_data_word[word_length+1] = {0};
volatile boolean startup = true;
volatile boolean word_ready = false;
boolean first_round = true;
boolean changed = false;

void int_clock() {
  // update timings
  now = micros();
  clock_interval = now - last_clock;
  // ignore false clocks
  if (clock_interval < clock_duration/2) {
    return;
  }
  // update timings
  last_clock = now;
  // check for the first clock with some tolerance
  if (clock_interval > (clock_preamble-clock_preamble_tolerance) && clock_interval < (clock_preamble+clock_preamble_tolerance)) {
    startup = false;
    // a valid word is exactly the length of the word
    if (!word_ready && (bit_pos == word_length)) {
      // the previous word is valid
      detachInterrupt(0);
      word_ready = true;
      return;
    }
    bit_pos = 0;
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
  if (!startup) {
    if (word_ready) {
      for (int i=0; i<word_length; i++) {
        if (!first_round) {
          if (data_word[i] > previous_data_word[i]) {
            Serial.print(i, DEC);
            Serial.print(":1");
            Serial.print(',');
            changed = true;
          } else if (data_word[i] < previous_data_word[i]) {
            Serial.print(i, DEC);
            Serial.print(":0");
            Serial.print(',');
            changed = true;
          }
        }
        previous_data_word[i] = data_word[i];
      }
      first_round = false;
      // we printed, so don't heartbeat
      now = micros();
      if (changed) {
        Serial.println();
        digitalWrite(ledPin, HIGH);
        last_print = now;
      }
      // processing complete, attach the interrupt again
      word_ready = false;
      attachInterrupt(0, int_clock, CHANGE);
    }
    // print heartbeat (full state)
    print_interval = now - last_print;
    if (print_interval > print_frequency) {
      for (int i=0; i<word_length; i++) {
        Serial.print(data_word[i], DEC);
      }
      Serial.println();
      last_print = now;
    }
  }
  // sleep so that we're not processing while an interrupt may be busy
  delayMicroseconds(clock_idle*2);
  digitalWrite(ledPin, LOW);
}
