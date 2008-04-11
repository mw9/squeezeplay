/*
** Copyright 2007-2008 Logitech. All Rights Reserved.
**
** This file is subject to the Logitech Public Source License Version 1.0. Please see the LICENCE file for details.
*/

#define RUNTIME_DEBUG 1

#include "common.h"

#include "audio/mqueue.h"
#include "audio/fifo.h"
#include "audio/streambuf.h"
#include "audio/decode/decode.h"
#include "audio/decode/decode_priv.h"


#define DECODE_MAX_INTERVAL 100

#define DECODE_MQUEUE_SIZE 512


/* decoder thread */
static SDL_Thread *decode_thread;


/* current decoder state */
u32_t current_decoder_state = 0;
u32_t current_audio_state = 0;


/* state variables for the current track */
u32_t decode_num_tracks_started = 0;
u32_t decode_elapsed_samples = 0;
bool_t decode_first_buffer = FALSE;
u32_t current_sample_rate = 44100;


/* decoder fifo used to store decoded samples */
u8_t decode_fifo_buf[DECODE_FIFO_SIZE];
struct fifo decode_fifo;


/* decoder mqueue */
struct mqueue decode_mqueue;
static Uint32 decode_mqueue_buffer[DECODE_MQUEUE_SIZE / sizeof(Uint32)];


/* audio instance */
struct decode_audio *decode_audio;


/* decoder instance */
static struct decode_module *decoder;
static void *decoder_data;


/* installed decoders */
static struct decode_module *all_decoders[] = {
	&decode_tones,
	&decode_pcm,
	&decode_flac,
#ifdef _WIN32
	&decode_wma_win,
#endif
};


static void decode_resume_handler(void) {
	Uint32 start_jiffies;

	start_jiffies = mqueue_read_u32(&decode_mqueue);
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_resume_handler start_jiffies=%d", start_jiffies);

	// XXXX handle start_jiffies

	if (decoder) {
		current_decoder_state |= DECODE_STATE_RUNNING;
	}

	if (!fifo_empty(&decode_fifo)) {
		current_audio_state = DECODE_STATE_RUNNING;
	}

	DEBUG_TRACE("resume decode state: %x audio state %x", current_decoder_state, current_audio_state);
}


static void decode_pause_handler(void) {
	Uint32 interval;

	interval = mqueue_read_u32(&decode_mqueue);
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_pause_handler interval=%d", interval);

	current_decoder_state &= ~DECODE_STATE_RUNNING;
	current_audio_state &= ~DECODE_STATE_RUNNING;

	DEBUG_TRACE("pause decode state: %x audio state %x", current_decoder_state, current_audio_state);
}


static void decode_skip_ahead_handler(void) {
	Uint32 interval;

	interval = mqueue_read_u32(&decode_mqueue);
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_skip_ahead_handler interval=%d", interval);

	// XXXX
}


static void decode_stop_handler(void) {
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_stop_handler");

	current_decoder_state = 0;
	current_audio_state = 0;

	if (decoder) {
		decoder->stop(decoder_data);

		decoder = NULL;
		decoder_data = NULL;
	}

	decode_first_buffer = FALSE;
	decode_num_tracks_started = 0;
	decode_output_end();

	streambuf_flush();
}


static void decode_flush_handler(void) {
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_flush_handler");

	current_decoder_state = 0;

	if (decoder) {
		decoder->stop(decoder_data);

		decoder = NULL;
		decoder_data = NULL;
	}

	decode_first_buffer = FALSE;
	decode_output_flush();
}


static void decode_start_handler(void) {
	Uint32 decoder_id, transition_type, transition_period, replay_gain, output_threshold, polarity_inversion;
	Uint32 i, num_params;
	Uint8 params[DECODER_MAX_PARAMS];

	decoder_id = mqueue_read_u32(&decode_mqueue);
	transition_type = mqueue_read_u32(&decode_mqueue);
	transition_period = mqueue_read_u32(&decode_mqueue);
	replay_gain = mqueue_read_u32(&decode_mqueue);
	output_threshold = mqueue_read_u32(&decode_mqueue);
	polarity_inversion = mqueue_read_u32(&decode_mqueue);

	num_params = mqueue_read_u32(&decode_mqueue);
	if (num_params > DECODER_MAX_PARAMS) {
		num_params = DECODER_MAX_PARAMS;
	}
	for (i = 0; i < num_params; i++) {
		params[i] = mqueue_read_u8(&decode_mqueue);
	}
	mqueue_read_complete(&decode_mqueue);

	DEBUG_TRACE("decode_start_handler decoder=%x num_params=%d", decoder_id, num_params);

	for (i = 0; i < sizeof(all_decoders); i++) {
		if (all_decoders[i]->id == decoder_id) {
			decoder = all_decoders[i];
			decoder_data = decoder->start(params, num_params);
			break;
		}
	}

	decode_first_buffer = TRUE;
	// XXXX decode_set_output_threshold(output_threshold);
	// XXXX decode_set_track_gain((replay_gain) ? replay_gain : FILTER_VOLUME_ONE);
	// XXXX decode_set_track_polarity_inversion(polarity_inversion);

	decode_output_begin();
}


static Uint32 decode_timer_interval(void) {
	if (decoder) {
		return decoder->period(decoder_data);
	}
	return DECODE_MAX_INTERVAL;
}


static int decode_thread_execute(void *unused) {
	DEBUG_TRACE("decode_thread_execute");

	while (true) {
		Uint32 timeout; // XXXX timer wrap around
		mqueue_func_t handler;

		timeout = SDL_GetTicks() + decode_timer_interval();
		//DEBUG_TRACE("timeout %d\n", timeout);

		while ((handler = mqueue_read_request(&decode_mqueue, timeout))) {
			DEBUG_TRACE("handling message");
			handler();
		}

		// XXXX new track started

		// XXXX check decoder state
		if (decoder && (current_decoder_state & DECODE_STATE_RUNNING)) {
			//DEBUG_TRACE("decode callback outbuf=%d", fifo_bytes_used(decode_fifo_rptr, decode_fifo_wptr, DECODE_FIFO_SIZE));
			decoder->callback(decoder_data);
		}

		// XXXX visualizer

		// XXXX buffer underrun
	}
}


/*
 * lua decoder interface
 */

static int decode_resume(lua_State *L) {
	Uint32 start_jiffies;

	/* stack is:
	 * 1: self
	 * 2: start_jiffies
	 */

	start_jiffies = (Uint32) luaL_optinteger(L, 2, 0);
	DEBUG_TRACE("decode_resume start_jiffies=%d", start_jiffies);

	if (mqueue_write_request(&decode_mqueue, decode_resume_handler, sizeof(Uint32))) {
		mqueue_write_u32(&decode_mqueue, start_jiffies);
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped resume message");
	}

	return 0;
}


static int decode_pause(lua_State *L) {
	Uint32 interval_ms;

	/* stack is:
	 * 1: self
	 * 2: start_jiffies
	 */

	interval_ms = (Uint32) luaL_optinteger(L, 2, 0);
	DEBUG_TRACE("decode_pause interval_ms=%d", interval_ms);

	if (mqueue_write_request(&decode_mqueue, decode_pause_handler, sizeof(Uint32))) {
		mqueue_write_u32(&decode_mqueue, interval_ms);
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped pause message");
	}

	return 0;
}


static int decode_skip_ahead(lua_State *L) {
	Uint32 interval_ms;

	/* stack is:
	 * 1: self
	 * 2: start_jiffies
	 */

	interval_ms = (Uint32) luaL_optinteger(L, 2, 0);
	DEBUG_TRACE("decode_skip_ahead interval_ms=%d", interval_ms);

	if (mqueue_write_request(&decode_mqueue, decode_skip_ahead_handler, sizeof(Uint32))) {
		mqueue_write_u32(&decode_mqueue, interval_ms);
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped skip_ahead message");
	}

	return 0;
}


static int decode_stop(lua_State *L) {
	/* stack is:
	 * 1: self
	 * 2: flush
	 */

	DEBUG_TRACE("decode_stop");

	if (mqueue_write_request(&decode_mqueue, decode_stop_handler, 0)) {
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped start message");
	}

	return 0;
}


static int decode_flush(lua_State *L) {
	/* stack is:
	 * 1: self
	 */

	DEBUG_TRACE("decode_flush");

	if (mqueue_write_request(&decode_mqueue, decode_flush_handler, 0)) {
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped flush message");
	}

	return 0;
}


static int decode_start(lua_State *L) {
	int num_params, i;

	DEBUG_TRACE("decode_start");

	/* stack is:
	 * 1: self
	 * 2: decoder
	 * 3: transition_type
	 * 4: transition_period
	 * 5: reply_gain
	 * 6: output_threshold
	 * 7: polarity_inversion
	 * 8: params...
	 */

	/* Reset the decoder state in calling thread to avoid potential
	 * race condition - we may incorrectly report a decoder underrun
	 * if we wait till the decoder thread resets it.
	 */
	current_decoder_state = 0;

	if (mqueue_write_request(&decode_mqueue, decode_start_handler, 0)) {
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 2, 0)); /* decoder */
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 3, 0)); /* transition_type */
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 4, 0)); /* transition_period */
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 5, 0)); /* replay_gain */
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 6, 0)); /* output_threshold */
		mqueue_write_u32(&decode_mqueue, (Uint32) luaL_optinteger(L, 7, 0)); /* polarity_inversion */

		num_params = lua_gettop(L) - 7;
		mqueue_write_u32(&decode_mqueue, num_params);
		for (i = 0; i < num_params; i++) {
			mqueue_write_u8(&decode_mqueue, (Uint8) luaL_optinteger(L, 8 + i, 0));
		}
		mqueue_write_complete(&decode_mqueue);
	}
	else {
		DEBUG_TRACE("Full message queue, dropped start message");
	}

	return 0;
}

static int decode_status(lua_State *L) {
	lua_newtable(L);

	// XXXX fifo mutex lock

	lua_pushinteger(L, fifo_bytes_used(&decode_fifo));
	lua_setfield(L, -2, "outputFull");

	lua_pushinteger(L, decode_fifo.size);
	lua_setfield(L, -2, "outputSize");

	lua_pushinteger(L, (u32_t)(((u64_t)decode_elapsed_samples * 1000) / current_sample_rate));
	lua_setfield(L, -2, "elapsed");

	lua_pushinteger(L, decode_num_tracks_started);
	lua_setfield(L, -2, "tracksStarted");

	// XXXX fifo mutex unlock


	lua_pushinteger(L, streambuf_get_usedbytes());
	lua_setfield(L, -2, "decodeFull");

	lua_pushinteger(L, streambuf_get_size());
	lua_setfield(L, -2, "decodeSize");


	lua_pushinteger(L, current_decoder_state);
	lua_setfield(L, -2, "decodeState");

	lua_pushinteger(L, current_audio_state);
	lua_setfield(L, -2, "audioState");

	return 1;
}

static const struct luaL_Reg decode_f[] = {
	{ "resume", decode_resume },
	{ "pause", decode_pause },
	{ "skipAhead", decode_skip_ahead },
	{ "stop", decode_stop },
	{ "flush", decode_flush },
	{ "start", decode_start },
	{ "status", decode_status },
	{ NULL, NULL }
};


int luaopen_decode(lua_State *L) {
	/* initialise audio output */
	decode_audio = &decode_portaudio;
	decode_audio->init();

	fifo_init(&decode_fifo, DECODE_FIFO_SIZE);

	mqueue_init(&decode_mqueue, decode_mqueue_buffer, sizeof(decode_mqueue_buffer));

	/* start decoder thread */
	decode_thread = SDL_CreateThread(decode_thread_execute, NULL);

	/* register lua functions */
	luaL_register(L, "squeezeplay.decode", decode_f);

	return 0;
}

