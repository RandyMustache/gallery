#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Generate a Jekyll gallery from a directory containing pictures
# Distributed under the terms of the MIT license
# (c) 2013 Adolfo Villafiorita
#

require 'getoptlong'
require 'exifr'

##############################################################################

#
# Filename utilities
#

def thumb_filename(filename)
  suffix_filename(filename, "thumb")
end

def page_filename(filename)
  suffix_filename(filename, "page")
end

# return true if the filename contains one of the suffixes used for
# automatically generated files ...
# ... that is: return true is filename contains "-thumb" or "-page"
#
# this is used to make sure we do not call the converter for files
# which we already generate
def is_suffixed?(filename)
  filename.include?("-thumb") or filename.include?("-page")
end

def suffix_filename(file, suffix)
  dirname = File.dirname(file)
  extension = File.extname(file)
  basename = File.basename(file, extension)

  dirname + "/" + basename + "-" + suffix + extension
end

##############################################################################

# 
# Generate a URL from a pathname, according to the following strategy:
#
# - if URL is empty, return the file basename (so that the references are
#   good for files in the same directory in which the link appears ... the
#   default for the gallery generator)
#
# - if URL is not empty, concatenate the URL with the filename. The
#   generated URLs are good if the pathname of file is the same as the
#   deployment structure of the resulting website 
#   (in the current implementation this happens if the script is called
#   from the root of the jekyll website)
#
# Moreover, if the gen_page flag is specified, the extension is
# changed to ".html"
#
# Example:
#   gen_link("", "/a/b/c/d.jpg", false) => "d.jpg"
#   gen_link("", "/a/b/c/d.jpg", true)  => "d.html"
#
#   gen_link("http://www.example.com", "/a/b/c/d.jpg", false) =>
#     http://www.example.com/a/b/c/d.jpg
#

def gen_link(url, file, gen_page)
  dirname = File.dirname(file)
  extension = File.extname(file)
  basename = File.basename(file, extension)

  if url != "" then
    url + (url.end_with?("/") ? "" : "/") + 
      dirname + "/" + basename + (gen_page ? ".html" : extension)
  else
    basename + (gen_page ? ".html" : extension)
  end
end

##############################################################################

#
# High level functions
#

def puts_help
  puts <<-eos
Usage: 

  create_gallery [--pages] [--url URL] [--geometry <geometry>] <directory> ...

Input:  <directory> ... one or more directory with JPG or PNG pictures
Output: a set of Jekyll file to present the pictures as a gallery

Optional arguments:

  --geometry NNNxMMM generate thumbnails of given geometry (for the gallery
                     file)
  --pages            generate one individual page per picture (rather than
                     having the gallery point directly to the pictures)
  --url URL          make all links absolute

Some examples of thumb geometries: 330x220, 210x150 (app default), 90x90
eos
end

#
# Converters: thumbnail generators
#

def generate_thumbs(gallery_name, geometry)
  Dir.glob("#{gallery_name}/*.{jpg,png}").each do |file|
    # skip if the file is a thumbnail or a page file
    if not is_suffixed?(file)
      system("convert -thumbnail #{geometry} '#{file}' '#{thumb_filename(file)}'")
    end
  end
end

#
# Generate the gallery index file
#

def generate_index(gallery_name, url, gen_page)
  File.open(gallery_name + "/index.textile", 'w') do |f|
    # header
    f.puts <<-eos
---
title: #{File.basename(gallery_name)}
layout: gallery
---
eos
    #
    # list of images, using a gallerific compatible markup
    # (ul.gallery > li > ( a > img.thumb | div.caption))
    #
    f.puts "<ul class=\"gallery\">"
    Dir.glob("#{gallery_name}/*.{jpg,png}").each do |file|

      if not is_suffixed?(file)
        f.puts <<-eos
  <li>
    <a href=\"#{gen_link(url, file, gen_page)}\">
      <img src=\"#{gen_link(url, thumb_filename(file), false)}\" class=\"thumb\">
    </a>
    <div class=\"caption\">
       <span class=\"title\">#{File.basename(file)}</span> <br />
       #{exif_data_to_html(file)}
    </div>
  </li>
eos
      end
    end
    f.puts "</ul>"
  end
end


#
# generate the thumbnails
#
def generate_pages(gallery_name, url)
  # collect the list of pages, to generate prev and next links
  pages = Array.new
  Dir.glob("#{gallery_name}/*.{jpg,png}").each do |file|
    if not is_suffixed?(file)
      pages << file
    end
  end

  # generate one page per file
  (0..pages.size - 1).each do |i|
    # links to previous and next pages
    prev_page = i > 0 ? gen_link(url, pages[i - 1], true) : ""
    page = pages[i]
    next_page = i < (pages.size - 1) ? gen_link(url, pages[i + 1], true) : ""

    # like the image file with ".textile" instead of the image extension
    page_name = gallery_name + "/" + File.basename(page, File.extname(page)) + ".textile"
    File.open(page_name, 'w') do |f|
      f.puts <<-eos
---
title: #{File.basename(page)}
layout: gallery_page
img: #{gen_link(url, page, false)}
#{("prev: " + prev_page) if prev_page != ""}
#{("next: " + next_page) if next_page != ""}
gallery: "#{File.basename(gallery_name)}"
gallery_index: index.html
index: #{i+1}
total: #{pages.size}
#{exif_data_to_yaml(page)}
---
eos
    end
  end
end

##############################################################################

#
# Exif data manager
# (simplified version, get basic data about the picture)
#
#

def exif_data_to_html(file)
  # add EXIF data, if jpg and exif is defined
  if File.extname(file) == ".jpg" then
    exif = EXIFR::JPEG.new(file)

    "<div class=\"exif\">\n" +
    "  #{exif.date_time}\n" +
    "  model: #{exif.model}\n" +
    "  e: #{exif.exposure_time.to_s} f: #{exif.f_number.to_f}\n" +
    "  size: #{exif.width} x #{exif.height}\n" +
    "</div>"
  end
end

def exif_data_to_yaml(file)
  if File.extname(file) == ".jpg" then
    exif = EXIFR::JPEG.new(file)

    "date_time: #{exif.date_time}\n" +
    "model: #{exif.model}\n" + 
    "exposure: #{exif.exposure_time.to_s}\n" +
    "aperture: #{exif.f_number.to_f}\n" +
    "size: #{exif.width} x #{exif.height}"
  end
end


##############################################################################

#
# main
#

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
  [ '--geometry', '-g', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--url', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--pages', GetoptLong::NO_ARGUMENT ],
)

dirname  = nil
url      = ""
geometry = "210x150"
gen_page = false

opts.each do |opt, arg|
  case opt
    when '--help'
       puts_help
       exit 0
    when '--url'
       url = arg
    when '--geometry'
       geometry = arg
    when '--pages'
       gen_page = true
  end
end

# at least one directory name
if ARGV.length == 0
  puts "Missing <directory> argument (try --help)"
  exit 0
end

ARGV.each do |argv|
  dirname = argv
  # make sure there is no final slash in the gallery name
  gallery_name = dirname.end_with?("/") ? dirname[0..-2] : dirname

  generate_thumbs(gallery_name, geometry)
  generate_index(gallery_name, url, gen_page)
  generate_pages(gallery_name, url) if gen_page
end


