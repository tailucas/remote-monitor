// pins
const byte ledPin = 13;
const byte interruptPin = 2;
const byte dataPin = 3;
// timing constants
const int clock_duration = 220;
const int clock_duration_tolerance = clock_duration/10;
const int clock_preamble = clock_duration*2;
const int clock_preamble_tolerance = clock_preamble/10;
const int clock_idle = 6000;
// for printing
unsigned long last_print_ts = 0;
unsigned long last_print_interval = 0;
const long print_interval = 10000000;
// interrupt routine variables
volatile unsigned long now = 0;
volatile unsigned long last_clock_ts = 0;
volatile unsigned long clock_interval = 0;
volatile int bit_pos = 0;
volatile unsigned long data_word1 = 0;
volatile unsigned long prev_data_word1 = 0;
volatile unsigned long data_word2 = 0;
volatile unsigned long prev_data_word2 = 0;
volatile boolean word_ready = false;
volatile boolean in_word = false;
volatile boolean changed = false;
void int_clock() {
  // update timings
  now = micros();
  clock_interval = now - last_clock_ts;
  // update timings
  last_clock_ts = now;
  // check for the first clock with some tolerance
  if (clock_interval > (clock_preamble-clock_preamble_tolerance) && clock_interval < (clock_preamble+clock_preamble_tolerance)) {
    in_word = true;
    // reset the bit position unconditionally
    bit_pos = 0;
  } else if (!in_word) {
    return;
  } else if (clock_interval > (clock_duration+clock_duration_tolerance) || clock_interval < (clock_duration-clock_duration_tolerance)) {
    // abandon this word because the timing is off
    in_word = false;
    return;
  }
  // allow the edge to dissipate
  delayMicroseconds(100);
  // read the data (goes low) and shift
  if (digitalRead(dataPin) == LOW) {
    // set
    if (bit_pos < 32) {
      data_word1 |= ((unsigned long)1 << (31-bit_pos));
    } else {
      data_word2 |= ((unsigned long)1 << (31-(bit_pos-32)));
    }
  } else {
    // unset
    if (bit_pos < 32) {
      data_word1 &= ~((unsigned long)1 << (31-bit_pos));
    } else {
      data_word2 &= ~((unsigned long)1 << (31-(bit_pos-32)));
    }
  }
  // shift
  bit_pos++;
  // exit
  if (bit_pos >= 64) {
    detachInterrupt(0);
    if (data_word1 != prev_data_word1 || data_word2 != prev_data_word2) {
      changed = true;
    } else {
      changed = false;
    }
    //(re)set
    prev_data_word1 = data_word1;
    prev_data_word2 = data_word2;
    bit_pos = 0;
    in_word = false;
    word_ready = true;
  }
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
    // print immediately upon change or regularly for heartbeat
    last_print_interval = micros() - last_print_ts;
    if (changed || (last_print_interval > print_interval)) {
      Serial.print(data_word1, HEX);
      Serial.print(',');
      Serial.println(data_word2, HEX);
      last_print_ts = micros();
    }
    // processing complete, latch and attach the interrupt again
    word_ready = false;
    attachInterrupt(0, int_clock, CHANGE);
  }
  // sleep so that we're not processing while an interrupt may be busy
  delayMicroseconds(clock_idle*2);
}
