// pins
const byte ledPin = 13;
const byte interruptPin = 2;
const byte dataPin = 3;
// timing constants
const int clock_duration = 220;
const int clock_preamble = clock_duration*2;
const int clock_preamble_tolerance = clock_preamble/10;
const int clock_idle = 6000;
const unsigned long validity_mask2 = 0x2AAAAAA;
// for printing
unsigned long last_print_ts = 0;
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
volatile int sample_value = 0;
volatile int values_sampled = 0;
void int_clock() {
  // update timings
  now = micros();
  clock_interval = now - last_clock_ts;
  // check for the first clock with some tolerance
  if (clock_interval > (clock_preamble-clock_preamble_tolerance) && clock_interval < (clock_preamble+clock_preamble_tolerance)) {
    in_word = true;
    // reset the bit position unconditionally
    bit_pos = 0;
  } else if (clock_interval < (clock_duration/2)) {
    // ignore this clock because it is too short
    return;
  }
  // update timings
  last_clock_ts = now;
  if (!in_word) {
    return;
  }
  // sample the value for half of the clock interval and an odd number of times
  sample_value = 0;
  values_sampled = 0;
  do {
    sample_value += digitalRead(dataPin);
    values_sampled++;
  } while (((micros() - last_clock_ts) < (clock_duration / 2)) && ((values_sampled & 1) != 0));
  // threshold the sampled value
  if (sample_value < (values_sampled / 2)) {
    sample_value = LOW;
  } else {
    sample_value = HIGH;
  }
  // read the data (goes low) and shift
  if (sample_value == LOW) {
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
    // validate each word based on the expected mask pattern
    if (data_word2 & validity_mask2 != 0) {
      bit_pos = 0;
      in_word = false;
      return;
    }
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
  pinMode(dataPin, INPUT);
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
    if (changed || ((micros() - last_print_ts) > print_interval)) {
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
