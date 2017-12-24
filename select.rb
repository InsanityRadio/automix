#!/bin/env ruby
require 'rjoystick'
require 'atem'
require 'mysql2'
require 'em-websocket'
require 'json'

require_relative 'config'

$stdout.sync = true
$stderr.sync = true

$AUDIO_THRESHOLD = 858803 * 2
$JOYSTICK = "/dev/input/js0"
$DATABASE = Mysql2::Client.new($database_opts)

puts ".: STARTING SCRIPT :."

class Inputs
	def initialize mapping, mixer
		@mapping = mapping
		@mixer = mixer
		@k = Rjoystick::Device.new($JOYSTICK)
		Thread.new do
			loop do
				begin
					e = @k.event
					handle_event e
				rescue
					STDERR.puts "Error in Joystick thread"
					STDERR.p $!
					@k.close rescue nil
					@k = Rjoystick::Device.new($JOYSTICK)
				end
			end
		end

	end

	def auto= auto_val
		@mixer.auto = auto_val
		broadcast_message c: 'a', d: auto_val
	end

	def auto2= break_val
		@mixer.break_mode = break_val
		broadcast_message c: 'a2', d: break_val
	end

	def force_prev short_name
		puts "Forcing #{short_name} PREV"
		@mixer.preview_camera @mixer.atem_inputs[short_name]
		puts "Done!"
	end

	def force_pgm short_name
		puts "Forcing #{short_name} PGM"
		@mixer.live_camera @mixer.atem_inputs[short_name]
		puts "Done!"
	end

	def handle_event e
		return unless e.type == Rjoystick::Event::JSBUTTON
		return unless @mapping[e.number] != nil
		e.value == 1 ? @mixer.enable(@mapping[e.number]) : @mixer.disable(@mapping[e.number])
	end
end

class VisionMixer

	attr_accessor :close, :wide, :auto, :current_camera, :prev_camera, :break_mode

	def initialize ip, close, wide, slate

		@ip = ip
		@close = close
		@wide = wide
		@break = true
		@current_camera = wide[0]
		@auto = true
		@break_mode = true

		connect!

		@close.map! { | w | @atem.inputs[w] }
		@wide.map! { | w | @atem.inputs[w] }

		@slate = @atem.inputs[slate]

	end
	def loop!
		sleep 0
		loop do

			if !@auto
				reset_peaks
				sleep 1
				next
			end
			select_camera
			preview_camera(@new_camera)
			sleep 0
			# Make the camera live then start immediately gathering data again
			live_camera @new_camera
			reset_peaks
			sleep 2

		end

	end

	def atem_inputs
		@atem.inputs
	end

	def connect!

		@atem = ATEM.connect(@ip)
		@atem.use_audio_levels = true
		@atem.inputs[@current_camera].program

	end
	
	def enable camera
		p "Enabling #{camera}"
		camera = @atem.inputs[camera]
		@close << camera unless @close.include? camera
		reload
	end

	def reload
		old_break = @break
		@break = @close.length == 0
		return unless old_break != @break
		# Store it in the database - if there's now a break, end the current link. Otherwise, open one. 
		begin
			if @break
				$DATABASE.query "UPDATE link_history SET end_date = CURRENT_TIMESTAMP() WHERE end_date = 0;"
			else
				$DATABASE.query "INSERT INTO link_history (start_date, end_date) VALUES (CURRENT_TIMESTAMP(), 0);"
			end
		rescue
			STDERR.puts "SQL Update failed!"
			STDERR.send :p, $!
		end

		select_camera
		preview_camera(@new_camera)
		live_camera(@new_camera)

	end

	def disable camera
		p "Disabling #{camera}"
		camera = @atem.inputs[camera]
		@close.delete camera
		reload
	end

	def select_camera

		begin

			@new_camera = (@wide + @close).sample

			if @break

				@new_camera = @break_mode ? @slate : @wide.sample
				raise "Done"

			end
			
			if @wide.include? @current_camera

				if Random.rand(3) == 0
					@new_camera = @wide.sample
					raise "Done"
				end

				highest = [nil, $AUDIO_THRESHOLD]
				p @close.length
				@close.each do | cam |

					maxim = [cam.audio.levels[:left_peak], cam.audio.levels[:right_peak]].max
					highest = [cam, maxim] if maxim > highest[1]

				end

				if highest[0] != nil

					p highest
					@new_camera = highest[0]
					raise "Done"

				end

			end

			if @close.include? @current_camera

				if Random.rand(3) == 0
					@new_camera = @wide.sample
					raise "Done"
				end

				@new_camera = @close.sample
				raise "Done"

			end

			@new_camera = @wide.sample

		rescue
			p $!
			p $?
		end

		debug "Selected camera #{@new_camera.name}"

	end

	def preview_camera new_camera

		return if @prev_camera == new_camera or new_camera == nil

		@prev_camera = new_camera
		@prev_camera.preview 
		broadcast_message c: 'prev', d: new_camera.short_name

	end

	def live_camera new_camera

		return if @current_camera == new_camera or new_camera == nil 

		debug "#{new_camera.name} is live"

		new_camera.program 
		@current_camera = new_camera
		broadcast_message c: 'pgm', d: new_camera.short_name

	end

	def reset_peaks

		@atem.reset_audio_peaks

	end

	private
	def info message

		puts "[ INFO ]  #{message}"

	end

	def debug message

		puts "[ DEBUG ] #{message}" if $debug

	end

end

$debug = true
# v = VisionMixer.new $IP, ['Pres', 'Gst'], ['Wide'], 'MP1'
$vision = v = VisionMixer.new $IP, [], ['Wide'], 'MP1'
$inputs = Inputs.new ['Pres', 'Gst', 'Gst'], v
Thread.abort_on_exception = true
Thread.new { v.loop! }

$clients = []

def broadcast_message message = {}

	message = message.to_json
	EM.next_tick {
		$clients.each do | ws |
			ws.send message 
		end
	}

end

EM.run {

	EM::WebSocket.run(:host => "0.0.0.0", :port => 16969) do | ws |

		auth = false

		ws.onopen { | handshake |

			if handshake.query['token'] != $TOKEN
				ws.close
				return
			end
			$clients << ws 
			
			ws.send({ c: 'a', d: $vision.auto }.to_json) rescue nil 
			ws.send({ c: 'a2', d: $vision.break_mode }.to_json) rescue nil 
			ws.send({ c: 'prev', d: $vision.prev_camera.short_name }.to_json) rescue nil 
			ws.send({ c: 'pgm', d: $vision.current_camera.short_name }.to_json) rescue nil 

			auth = true

		}

		ws.onmessage { | message |

			next if !auth
			begin
				message = JSON.parse(message)

				case message['c']
				when 'a'
					$inputs.auto = !!message['d']
				when 'a2'
					$inputs.auto2 = !!message['d']
				when 'pgm'
					puts 'Forcing PGM'
					$inputs.force_pgm message['d'].to_s
				when 'prev'
					puts 'Forcing Prev'
					$inputs.force_prev message['d'].to_s
				end

				ws.send({ s: 1 }.to_json)

			rescue
				p $!
				p $?
			end

		}

		ws.onclose { 

			puts "Websocket closed!"
			$clients.delete ws
			# If we lose our last client, return to auto mode
			# Otherwise it can get toootally effed up
			if $clients.length == 0
				$inputs.auto = true
				$inputs.auto2 = true
			end

		}

	end

}
