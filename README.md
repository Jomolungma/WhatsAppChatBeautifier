# WhatsAppChatBeautifier

WhatsAppChatBeautifier is a tool to render WhatsApp and Threema chats into
HTML.

WhatsApp and Threema allow exporting chat histories in ZIP format.
WhatsAppChatBeautifier reads this exported chat and formats it as HTML
for viewing, archiving or printing.

## Prerequisites

WhatsAppChatBeautifier requires Ruby, and optionally the "rubyzip" and
"rubyXL" gems.

## Usage

Basic usage:

```
ruby c2h.rb <Input-File/Dir/Zip> --outputDirectory=DIR [--outputType=Chat/HTML]
```

The input can be:
- A directory, ZIP file or text file exported from WhatsApp.
- A directory, ZIP file or text file exported from Threema.
- A directory, ZIP file or XLSX file exported from Elcomsoft Explorer
  for WhatsApp.

Multiple input files can be given to merge chat sessions that were, e.g.,
exported at different points in time.

The output directory is created; if it exists, it should be empty. The file
"index.html" is generated in the output directory and can be opened with any
browser.

The output type defaults to "HTML". Alternatively, chats can also be
re-exported as WhatsApp chat files, which can be useful in some archiving
scenarios.

## Options

- `--outputType=[Chat/HTML]` Select output type: HTML or WhatsApp chat text
file. Defaults to HTML.
- `--outputDirectory=<Dir>` Output directory. Will be created if it does not
exist.
- `--chatName=<name>` Select the name of the chat to export. Can be a
partial name. (Only relevant when the input file is an export from Elcomsoft
Explorer for WhatsApp).
- `--printChatNames` No conversion, just print the names of all chats in
the input file. (Only relevant when the input file is an export from Elcomsoft
Explorer for WhatsApp).
- `--printChatParticipants` No conversion, just print the names of all
participants in this chat. (Useful for mapping participant names in a group
chat with the `--map` option.)
- `--from=yyyy[-mm[-dd]]` Select messages from this date or later.
- `--to=yyyy[-mm[-dd]]` Select messages from until this date.
- `--me=<Name>` Identify one of the chat participants as yourself (can be
a partial name).
- `--map=<sender=Name>` Replace the name of _sender_ (can be a partial)
with _Name_, e.g., to replace phone numbers with readable names. This
option can be used multiple times.
- `--attachments=[Copy/Move]` Copy or move attachments to the output
directory. The default is neither. Note that inline images and media will
be broken if the output directory does not contain the attachment files
and this option is not used.
- `--renameAttachments` Rename attachments in the output directory to
have a "yyyy-mm-dddd" prefix, so that the attachments appear in chronological
order when opening the output directory in a file explorer.
- `--title=<Title>` `(HTML output only)` Document title to use.
- `--split=[month,year]` Instead of a single big index.html file, split the chat
into monthly or annual pages. `(HTML output only)`
- `--emojiDir=<Dir>` Find inline emoji images in this directory. See Emojis
section below. `(HTML output only)`
- `--backgroundImag=<fileName>` Use this image file as a background image.
See Background Images section below. `(HTML output only)`
- `--imageSize=<Width>x<Height>` Scale large images so that the embedded
image does not exceed this maximum. For larger images, a link to the full-size
images is generated. The default is 320x240. `(HTML output only)`
- `-v` Increase verbosity during operation.
- `-h` Print a summary of all options.

## Notes

When processing chats that were exported from WhatsApp, the `--me` option
must be given to identify yourself as a chat participant, so that your
messages are rendered on the right-hand side.

In two-person chats, the name of the sender is not printed.

Most formatting is defined by the style sheet `c2h.css` in this directory.

The style sheet, all media files, and all used emoji images, are copied to the
output directory, so that it is self-contained.

## Emojis

There are multiple options for handling emoticons that may be part of a conversation.
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

The `Background Images` folder contains sample background images for the
WhatsApp conversations. These images have been downloaded from
[Pixabay](https://pixabay.com/de/). Images and Videos on Pixabay are
released under Creative Commons CC0.

## Threema

WhatsAppChatBeautifier also includes preliminary support for single chats
exported from the [Threema](https://threema.ch/) messenger.

However, WhatsAppChatBeautifier is unable to decrypt the ZIP file format
used by Threema. Please unzip the ZIP file using software that supports
AES encryption, such as [7-Zip](https://www.7-zip.org/) to extract the
ZIP file, then point WhatsAppChatBeautifier to the extracted contents.

In single chats, incoming messages use the sender `<<<`. You can use the
`--map` option to substitute `<<<` with a different name.

## Explorer for WhatsApp

The WhatsApp export feature is limited in size and functionality, and
restricted in some locations. The commercial software product
[Elcomsoft Explorer for WhatsApp](https://www.elcomsoft.de/exwa.html)
is available to extract the entire WhatsApp database. The contents of
the WhatsApp database (i.e., all conversations and attached media) can
be exported from Explorer for WhatsApp as a spreadsheet ("XLSX").
This spreadsheet can then be used as an input for WhatsAppChatBeautifier.

## Caveats

WhatsApp and Threma use localized strings in their exported chats, such
as "&lt;attached&gt;" translated to the phone's language to reference
attached media, and localized timestamps for its messages. Switch your
phone to English while exporting chats to avoid any localization issues.

Image captions and quoted messages are not exported by WhatsApp.

Dates are rendered in English, e.g., "April 13, 2018".
