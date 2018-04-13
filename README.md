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

- `--input=_<Dir/File>_` Load chat from a ZIP file or directory. This option
can be used multiple times to merge chat sessions.
- `--outputDirectory=_<Dir>_` Generate output in this directory, which will be
created or emptied.
- `--title=_<Title>_` HTML title to use.
- `--me=_<SenderId>_` Messages by this sender are right-aligned.
- `--map=_<SenderId=name>` In HTML output, replace all sender ids with the
_substring_ **SenderId** with **name**, e.g., to replace phone numbers with
readable names. This option can be used multiple times.
- `--index=_[month,year]` Instead of a single big index.html file, split the
chat into monthly or annual files.
- `--imageSize=_<Width>x<Height>_` Scale large images so that the embedded
image does not exceed this maximum. For larger images, a link to the full-size
images is generated. Default 320x240.
- `--emojiDir=_<Dir>_` Find inline emoji images in this directory. See Emojis
section below.
- `--emojiSize=_<Width>x<Height>_` Size of inline emoji images, default 20x20.

## Notes

In two-person chats, the name of the sender is not printed.

In two-person chats, if the `--me` option is not given, one of the two
participants is randomly chosen as "me" (i.e., rendered on the right-hand side).

All formatting is defined by the style sheet `c2h.css` in this directory.

The style sheet, all media files, and all used emoji images, are copied to the
output directory, so that it is self-contained.

## Emojis

WhatsApp chats may contain Unicode. The Unicode consortium maintains a
list of emoticons [here](http://www.unicode.org/emoji/charts/emoji-list.html).
When the `--emojiDir` option is not used, emoticons are left as-is, i.e., using
the appropriate Unicode character, and your Web browser should render them.
However, this does not always work due to lack of browser support or missing
emoticons in your installed font files. Therefore, WhatsAppChatBeautifier
supports replacing emoticon characters with inline images.

For this to work, the given directory must contain image files for each emoticon.

The `uel2img.rb` script can be used to extract the list of emoticons from the
Unicode consortium's Web page and to populate a directory that can be used by
WhatsAppChatBeautifier.

Note that _variation selectors_ and _skin tone modifiers_ are discarded in
this process.

## Caveats

WhatsApp uses some localized strings in its exported chats, such as "<attached>"
for attached media, and its message timestamps. WhatsAppChatBeautifier might not
work with other locales as it was tested with (English, German).

Image captions are not exported by WhatsApp.

Dates are rendered in English, e.g., "April 13, 2018".
