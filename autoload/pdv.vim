" PDV (phpDocumentor for Vim)
" ===========================
"
" Version: 2.0.0alpha1
" 
" Copyright 2005-2011 by Tobias Schlitt <toby@php.net>
"
" Provided under the GPL (http://www.gnu.org/copyleft/gpl.html).
"
" This script provides functions to generate phpDocumentor conform
" documentation blocks for your PHP code. The script currently
" documents:
" 
" - Classes
" - Methods/Functions
" - Attributes
"
" All of those supporting PHP 5 syntax elements. 
"
" Beside that it allows you to define default values for phpDocumentor tags 
" like @version (I use $id$ here), @author, @license and so on. 
"
" For function/method parameters and attributes, the script tries to guess the 
" type as good as possible from PHP5 type hints or default values (array, bool, 
" int, string...).
"
" You can use this script by mapping the function PhpDoc() to any
" key combination. Hit this on the line where the element to document
" resides and the doc block will be created directly above that line.

let s:old_cpo = &cpo
set cpo&vim

"
" Regular expressions 
" 

let s:comment = ' *\*/ *'

let s:regex = {}

" (private|protected|public)
let s:regex["scope"] = '\(private\|protected\|public\)'
" (static)
let s:regex["static"] = '\(static\)'
" (abstract)
let s:regex["abstract"] = '\(abstract\)'
" (final)
let s:regex["final"] = '\(final\)'

" [:space:]*(private|protected|public|static|abstract)*[:space:]+[:identifier:]+\([:params:]\)
let s:regex["function"] = '^\(\s*\)\([a-zA-Z ]*\)function\s\+\([^ (]\+\)\s*('
" [:typehint:]*[:space:]*$[:identifier]\([:space:]*=[:space:]*[:value:]\)?
let s:regex["param"] = ' *\([^ &]*\)\s*\(&\?\)\$\([^ =)]\+\)\s*\(=\s*\(.*\)\)\?$'

" [:space:]*(private|protected|public\)[:space:]*$[:identifier:]+\([:space:]*=[:space:]*[:value:]+\)*;
let s:regex["attribute"] = '^\(\s*\)\(\(private\s*\|public\s*\|protected\s*\|static\s*\)\+\)\s*\$\([^ ;=]\+\)[ =]*\(.*\);\?$'

" [:spacce:]*(abstract|final|)[:space:]*(class|interface)+[:space:]+\(extends ([:identifier:])\)?[:space:]*\(implements ([:identifier:][, ]*)+\)?
let s:regex["class"] = '^\(\s*\)\(.*\)\s*\(interface\|class\)\s*\(\S\+\)\s*\([^{]*\){\?$'

let s:regex["types"] = {}

let s:regex["types"]["array"]  = "^array *(.*"
let s:regex["types"]["float"]  = '^[0-9]*\.[0-9]\+'
let s:regex["types"]["int"]    = '^[0-9]\+'
let s:regex["types"]["string"] = "['\"].*"
let s:regex["types"]["bool"] = "\(true\|false\)"

let s:regex["indent"] = '^\s*'

let s:mapping = [
    \ {"regex": s:regex["function"],
    \  "function": function("pdv#ParseFunctionData"),
    \  "template": "function"},
    \ {"regex": s:regex["attribute"],
    \  "function": function("pdv#ParseAttributeData"),
    \  "template": "attribute"},
    \ {"regex": s:regex["class"],
    \  "function": function("pdv#ParseClassData"),
    \  "template": "class"},
\ ]

func! pdv#DocumentLine()
	let l:docline = line(".")
	let l:linecontent = getline(l:docline)


	for l:parseconfig in s:mapping
		if match(l:linecontent, l:parseconfig["regex"]) > -1
			return pdv#Document(l:docline, l:parseconfig)
		endif
	endfor

	throw "Cannot document line: No matching syntax found."
endfunc

func! pdv#Document(docline, config)
	let l:Parsefunction = a:config["function"]
	let l:data = l:Parsefunction(a:docline)
	let l:template = pdv#GetTemplate(a:config["template"] . '.tpl')
	call append(a:docline - 1, pdv#ProcessTemplate(l:template, l:data))
	" TODO: Assumes phpDoc style comments (indent + 4).
	call cursor(a:docline + 1, len(l:data["indent"]) + 4)
endfunc

func! pdv#GetTemplate(filename)
	return g:pdv_template_dir . '/' . a:filename
endfunc

func! pdv#ProcessTemplate(file, data)
	let l:docblock = vmustache#RenderFile(a:file, a:data)
	let l:lines = split(l:docblock, "\n")
	return map(l:lines, '"' . a:data["indent"] . '" . v:val')
endfunc

func! pdv#ParseClassData(line)
	let l:text = getline(a:line)

	let l:data = {}
	let l:matches = matchlist(l:text, s:regex["class"])

	let l:data["indent"] = matches[1]
	let l:data["name"] = matches[4]
	let l:data["interface"] = matches[3] == "interface"
	let l:data["abstract"] = pdv#GetAbstract(matches[2])
	let l:data["final"] = pdv#GetFinal(matches[2])

	if (!empty(l:matches[5]))
		call pdv#ParseExtendsImplements(l:data, l:matches[5])
	endif
	" TODO: abstract? final?

	return l:data
endfunc

func! pdv#ParseExtendsImplements(data, text)
	let l:tokens = split(a:text, '\(\s*,\s*\|\s\+\)')

	let l:extends = 0
	for l:token in l:tokens
		if (tolower(l:token) == "extends")
			let l:extends = 1
			continue
		endif
		if l:extends
			let a:data["parent"] = {"name": l:token}
			break
		endif
	endfor

	let l:implements = 0
	let l:interfaces = []
	for l:token in l:tokens
		if (tolower(l:token) == "implements")
			let l:implements = 1
			continue
		endif
		if (l:implements && tolower(l:token) == "extends")
			break
		endif
		if (l:implements)
			call add(l:interfaces, {"name": l:token})
		endif
	endfor
	let a:data["interfaces"] = l:interfaces

endfunc

func! pdv#ParseAttributeData(line)
	let l:text = getline(a:line)

	let l:data = {}
	let l:matches = matchlist(l:text, s:regex["attribute"])

	let l:data["indent"] = l:matches[1]
	let l:data["scope"] = pdv#GetScope(l:matches[2])
	let l:data["static"] = pdv#GetStatic(l:matches[2])
	let l:data["name"] = l:matches[4]
	" TODO: Cleanup ; and friends
	let l:data["default"] = get(l:matches, 5, '')
	let l:data["type"] = pdv#GuessType(l:data["default"])

	return l:data
endfunc

func! pdv#ParseFunctionData(line)
	let l:text = getline(a:line)

	let l:data = pdv#ParseBasicFunctionData(l:text)
	let l:data["parameters"] = []

	let l:parameters = parparse#ParseParameters(a:line)

	for l:param in l:parameters
		call add(l:data["parameters"], pdv#ParseParameterData(l:param))
	endfor

	return l:data
endfunc

func! pdv#ParseParameterData(text)
	let l:data = {}

	let l:matches = matchlist(a:text, s:regex["param"])

	let l:data["reference"] = (l:matches[2] == "&")
	let l:data["name"] = l:matches[3]
	let l:data["default"] = l:matches[5]

	if (!empty(l:matches[1]))
		let l:data["type"] = l:matches[1]
	elseif (!empty(l:data["default"]))
		let l:data["type"] = pdv#GuessType(l:data["default"])
	endif

	return l:data
endfunc

func! pdv#ParseBasicFunctionData(text)
	let l:data = {}

	let l:matches = matchlist(a:text, s:regex["function"])

	let l:data["indent"] = l:matches[1]
	let l:data["scope"] = pdv#GetScope(l:matches[2])
	let l:data["static"] = pdv#GetStatic(l:matches[2])
	let l:data["name"] = l:matches[3]

	return l:data
endfunc

func! pdv#GetScope( modifiers )
	return matchstr(a:modifiers, s:regex["scope"])
endfunc

func! pdv#GetStatic( modifiers )
	return tolower(a:modifiers) =~ s:regex["static"]
endfunc

func! pdv#GetAbstract( modifiers )
	return tolower(a:modifiers) =~ s:regex["abstract"]
endfunc

func! pdv#GetFinal( modifiers )
	return tolower(a:modifiers) =~ s:regex["final"]
endfunc

func! pdv#GuessType( typeString )
	if a:typeString =~ s:regex["types"]["array"]
		return "array"
	endif
	if a:typeString =~ s:regex["types"]["float"]
		return "float"
	endif
	if a:typeString =~ s:regex["types"]["int"]
		return "int"
	endif
	if a:typeString =~ s:regex["types"]["string"]
		return "string"
	endif
	if a:typeString =~ s:regex["types"]["bool"]
		return "bool"
	endif
endfunc

let &cpo = s:old_cpo
