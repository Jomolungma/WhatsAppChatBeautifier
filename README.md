# WhatsAppChatBeautifier

WhatsAppChatBeautifier is a tool to render WhatsApp chats.

WhatsApp allows exporting and downloading chats in ZIP format.
WhatsAppChatBeautifier reads an exported chat and formats it as HTML for viewing,
archiving or printing.

## Prerequisites

WhatsAppChatBeautifier requires Ruby, and optionally the "rubyzip" gem.

## Usage

Basic usage:

```
ruby c2h.rb [<options>] --input=<File/Dir> --outputDirectory=DIR
```

The input can be either a ZIP file as exported from WhatsApp, or a directory
containing the contents of such a ZIP file.

The output directory is created; if it exists, its contents are overwritten.

The file "index.html" is generated in the output directory and can be opened
with any browser.

## Options

- `--input=<Dir/File>` Load chat from a ZIP file or directory. This option
can be used multiple times to merge chat sessions.
- `--outputDirectory=<Dir>` Generate output in this directory, which will be
created or emptied.
- `--title=<Title>` Document title to use.
- `--me=<SenderId>` Messages by this sender are right-aligned.
- `--map=<SenderId=name>` Replace all sender ids with the _substring_
**SenderId** with **name**, e.g., to replace phone numbers with readable
names. This option can be used multiple times.
- `--index=[month,year]` Instead of a single big index.html file, split the
chat into monthly or annual pages.
- `--imageSize=<Width>x<Height>` Scale large images so that the embedded
image does not exceed this maximum. For larger images, a link to the full-size
images is generated. The default is 320x240.
- `--emojiDir=<Dir>` Find inline emoji images in this directory. See Emojis
section below.
- `--backgroundImageName=<FileName>` Pick up a background image sample from this directory. See Background Images
section below.
- `--emojiSize=<Width>x<Height>` Size of inline emoji images, default 20x20.

## Notes

In two-person chats, the name of the sender is not printed.

In two-person chats, if the `--me` option is not given, one of the two
participants is randomly chosen as "me" (i.e., rendered on the right-hand side).

All formatting is defined by the style sheet `c2h.css` in this directory.

The style sheet, all media files, and all used emoji images, are copied to the
output directory, so that it is self-contained.

## Emojis

There are two options for handling emoticons that may be part of a conversation.
By default, emoticons are left as-is, as their original unicode characters, so
that the Web browser should render them. However, this does not always work
properly due to lack of browser support or missing emoticons in your installed
font files.

Therefore, WhatsAppChatBeautifier supports replacing emoticon characters with
inline images from a set of emoji image files using the `--emojiDir` option.
The given directory must contain image files for each emoticon. Two sources
of emoticon image files are supported.

First, the Unicode consortium maintains a list of emoticons
[here](http://www.unicode.org/emoji/charts/emoji-list.html). The `uel2img.rb`
script can be used to extract the list of emoticons from the Unicode
consortium's Web page and to populate a directory that can be used by
WhatsAppChatBeautifier.

Alternatively, the [noto-emoji](https://github.com/googlei18n/noto-emoji)
package includes emoji images. Both the PNG and SVG file sets can be used.

Note that _variation selectors_ are discarded in this process.

When the Unicode set is used, _skin tone modifiers_ are also discarded.

In summary, there are three options for treating emoticons:
- As-is, rendered by the browser.
- Replaced by images from the Unicode consortium, by way of the `uel2img.rb` script.
- Replaced by PNG or SVG images from the _noto-emoji_ package.

## Background Images

This folder contains sample background images for the WhatsApp conversations. 
These images have been downloaded from [Pixabay](https://pixabay.com/de/).
Images and Videos on Pixabay are released under Creative Commons CC0.

## Threema

WhatsAppChatBeautifier also includes preliminary support for single chats
exported from the [Threema](https://threema.ch/) messenger.

However, WhatsAppChatBeautifier is unable to decrypt the ZIP file format
used by Threema. Please unzip the ZIP file using software that supports
AES encryption, such as [7-Zip](https://www.7-zip.org/) to extract the
ZIP file, then point WhatsAppChatBeautifier to the extracted contents.

In single chats, incoming messages use the sender `<<<`, outgoing messages
the sender `>>>`. Use the `--map` option to map these sender ids to names.

## Caveats

WhatsApp and Threma use localized strings in its exported chats, such
as "<attached>" translated to the phone's language to reference attached
media, and localized timestamps for its messages. Switch your phone to
English while exporting chats to avoid any localization issues.

Image captions are not exported by WhatsApp.

Dates are rendered in English, e.g., "April 13, 2018".
