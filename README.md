# <img src="https://raw.githubusercontent.com/InsanityRadio/OnAirController/master/doc/headphones_dark.png" align="left" height=48 /> automix

automix (styled AutoMix) is a software vision mixer controller built for use at Insanity Radio. 

It is built to work with ATEM switchers, but you can probably hack it to work with something else.

## Setup

A blog post on the Insanity Tech blog should describe the hardware requirements for this quite well. https://tech.insanityradio.com/2017/09/24/how-to-automated-vision-mixing/

Copy config.rb.dist to config.rb, and edit the values. Import the database schema. This stores timestamps of fader open/closes, so you can easily pull video segs. 

Update your operating system kernel so it supports the latest joystick drivers (retro, but EL7 didn't support them initially - it does now). 

Install nginx and set up a location based on the nginx.conf file in the project root. Change the security token. This will hopefully become redundant in the future. 

In terms of software, run:

```shell
bundle install
./run.sh
```

## License

Copyright (C) 2017 Jamie Woods; Insanity Radio

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

