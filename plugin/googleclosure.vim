" Requirements:
" 1. g:ProjectSourceBasePath
" 2. g:GoogleClosureBasePath
" 3. g:GoogleClosureBin
" 4. g:GoogleClosureModule
" E.g. in project .vimrc:
" let g:ProjectSourceBasePath = '/Users/alex/Documents/work/sampleProject/src'
" let g:GoogleClosureBasePath = 'goog'
" let g:GoogleClosureModule = 'myModule'
" let g:GoogleClosureBin = '/Users/alex/Documents/tools/closure/bin'

let g:GoogleClosureTestTemplate = ['<!DOCTYPE html>','<html>','<head>','    <title>Google Closure Unit Tests - $PACKAGENAME$</title>','    <script src="$CLOSUREBASE$"></script>','    <script>','        goog.require("$PACKAGENAME$");','        goog.require("goog.testing.asserts");', '        goog.require("goog.testing.jsunit");', '    </script>','</head>','<body>','<script type="text/javascript">', '','</script>','</body>','</html>']
let g:GoogleClosureAutoRequire = 1
let g:GoogleClosureDeps = ''

function! GoogleClosure_GetBasePath()
    let currentFolder = expand('%:p:h')
    let currentFolder = substitute(currentFolder, g:ProjectSourceBasePath.'/', '', 'g')
    let pos = match(currentFolder, '/')
    let res = './'
    while pos != -1
        let pos = match(currentFolder, '/', pos+1)
        let res = res.'../'
    endwhile
    return res.g:GoogleClosureBasePath.'/'
endfunction

function! GoogleClosure_CalcDeps()
    let calcDeps = 'python '.g:GoogleClosureBin.'/calcdeps.py'
    let calcDeps = calcDeps.' -p '.g:ProjectSourceBasePath.'/'.g:GoogleClosureBasePath
    let calcDeps = calcDeps.' -p '.g:ProjectSourceBasePath.'/'.g:GoogleClosureModule
    let calcDeps = calcDeps.' -o deps'
    let calcDeps = calcDeps.' --output_file='.g:ProjectSourceBasePath.'/'.g:GoogleClosureBasePath.'/deps.js'
    system(calcDeps)
    echo 'Deps file rebuilt'
endfunction

function! GoogleClosure_JS_GetCurrentPackage()
    let end = line('$')
    if end == 1
        throw 'goog.provide not found'
    endif

    let sourceContent = join(getline(1,end))
    let res = matchlist(sourceContent,'goog\.provide([\s"'']\+\([^"'']\+\)')
    if len(res) == 0 || res[0] == ''
        throw 'goog.provide not found'
    endif
    return res[1]
endfunction

function! GoogleClosure_GetTestFile()
    return expand('%:r').'_test.html'
endfunction

function! GoogleClosure_MakeTest()
    if (expand('%:e') != 'js')
        echo 'Current file is not js file.'
    elseif (filereadable(GoogleClosure_GetTestFile()))
        execute 'e '.GoogleClosure_GetTestFile()
        echo 'Test package opened'
    else
        let testContent = join(g:GoogleClosureTestTemplate,'__SEPARATOR__')
        
        let testContent = substitute(testContent, '$PACKAGENAME\$', GoogleClosure_JS_GetCurrentPackage(), 'g')
        let testContent = substitute(testContent, '$CLOSUREBASE\$', GoogleClosure_GetBasePath().'/base.js', 'g')
        execute 'e '.GoogleClosure_GetTestFile()
        call setline(1,split(testContent, '__SEPARATOR__'))
    endif
endfunction

function! GoogleClosure_InsertLinesTo(lines, start, move)
    let currentLines = getline(a:start, line('$'))
    let lines = a:lines + currentLines
    call setline(a:start, lines)
    if a:move
        call cursor(a:start+len(a:lines),1)
    endif
endfunction

function! GoogleClosure_InsertLines(lines)
    let lines = a:lines+['']
    call GoogleClosure_InsertLinesTo(lines, line('.'), 1)
endfunction

function! GoogleClosure_JS_CheckName(name, visibility)
    let name = a:name
    if a:visibility == 'public'
        if strridx(a:name,'_') == (strlen(a:name) - 1)
            throw 'Public can''t ends with _'
        endif
    else
        if strridx(a:name,'_') != (strlen(a:name) - 1)
            let name .= '_'
        endif
    endif
    return name
endfunction

function! GoogleClosure_JS_Require(classOrInterfaceName)
    let index = strridx(a:classOrInterfaceName,'.')
    if index == -1
        return
    endif
    let package = strpart(a:classOrInterfaceName, 0, index)
    call GoogleClosure_JS_RequirePackage(package)
endfunction

function! GoogleClosure_JS_RequirePackage(packageName)
    if a:packageName == GoogleClosure_JS_GetCurrentPackage()
        return
    endif
    let end = line('$')
    if end == 1
        return
    endif
    let content = getline(1, end)
    let strToFind = 'goog\.require([''" ]\+'.substitute(a:packageName,'\.','\\.','g').'[''" ]\+);$'
    if match(content, strToFind) != -1
        return
    endif

    " we need latest goog.require or goog.provide
    let lastRequire = match(content, 'goog\.require(')
    let index = match(content, 'goog\.require(', lastRequire+1)
    while index != -1
        let lastRequire = index
        let index = match(content, 'goog\.require(', lastRequire+1)
    endwhile
    if lastRequire != -1
        let insertIndex = lastRequire+2
    else
        let requireIndex = match(content, 'goog\.provide(')
        if requireIndex == -1
            return
        endif
        let insertIndex = requireIndex+2
    endif

    let code = ['goog.require('''.a:packageName.''');']
    call GoogleClosure_InsertLinesTo(code, insertIndex, 0)
endfunction

function! GoogleClosure_JS_ParseClassDef(classDef)
    let classInfoList = matchlist(a:classDef, '\(public\|private\)\?[ ]*\([^ :<>]\+\)\?[ <>]*\([^ :$]\+\)\?[ :]*\(.\+\)\?')
    if len(classInfoList) == 0 || classInfoList[0] == ''
        throw 'Invalid class def'
    endif

    let res = {}
    let res["visibility"] = (classInfoList[1] == '') ? 'public' : classInfoList[1]
    let res["name"] = GoogleClosure_JS_CheckName(classInfoList[2], res["visibility"])
    let res["parent"] = classInfoList[3]
    let res["interfaces"] = (classInfoList[4] == '') ? [] : split(classInfiList[4],'[ ,;:]\+')
    let res["package"] = GoogleClosure_JS_GetCurrentPackage()
    return res
endfunction

function! GoogleClosure_JS_CreateClass(classDef)
    let classInfo = GoogleClosure_JS_ParseClassDef(a:classDef)

    let classDefinition = ['//------------------------------------------------------------------------------']
    let classDefinition += ['//','//        '.classInfo["name"].' class','//']
    let classDefinition += ['//------------------------------------------------------------------------------']
    let classDefinition += ['/**',' * TODO: Docs']
    
    if classInfo["visibility"] != 'public'
        let classDefinition += [' * @'.classInfo["visibility"]]
    endif

    let classDefinition += [' * @constructor']

    if classInfo["parent"] != ''
        let classDefinition += [' * @extends {'.classInfo["parent"].'}']
    endif

    for interface in classInfo["interfaces"]
        let classDefinition += [' * @implements {'.interface.'}']
    endfor

    let classDefinition += [' */']
    let classDefinition += [classInfo["package"].'.'.classInfo["name"].' = function() {']
    if classInfo["parent"] != ''
        let classDefinition += ['    '.classInfo["parent"].'.call(this);']
    endif
    let classDefinition += ['};']
    if classInfo["parent"] != ''
        let classDefinition += ['goog.inherits('.classInfo["package"].".".classInfo["name"].',']
        let classDefinition += ['              '.classInfo["parent"].');']
    endif
    call GoogleClosure_InsertLines(classDefinition)

    if (g:GoogleClosureAutoRequire)
        if classInfo["parent"] != ''
            call GoogleClosure_JS_Require(classInfo["parent"])
        endif
        for interface in classInfo["interfaces"]
            call GoogleClosure_JS_Require(interface)
        endfor
    endif
endfunction

function! GoogleClosure_JS_ParseInterfaceDef(interfaceDef)
    let interfaceInfo = matchlist(a:interfaceDef, '\(public\|private\)\?[ <>:;]*\([^ <>:;]\+\)\(.*\)\?')
    if len(interfaceInfo) == 0 || interfaceInfo[0] == ''
        throw 'Invalid interface signature'
    endif

    let res = {}
    let res["visibility"] = (interfaceInfo[1] == '') ? 'public' : interfaceInfo[1] 
    let res["name"] = GoogleClosure_JS_CheckName(interfaceInfo[2], res["visibility"])
    let res["parent"] = (interfaceInfo[3] == '') ? [] : split(interfaceInfo[3],'[ ;,<>:]\+')
    return res
endfunction

function! GoogleClosure_JS_CreateInterface(interfaceDef)
    let interface = GoogleClosure_JS_ParseInterfaceDef(a:interfaceDef)

    let interfaceDef  = ['//------------------------------------------------------------------------------']
    let interfaceDef += ['//','//        '.interface["name"].' interface','//']
    let interfaceDef += ['//------------------------------------------------------------------------------']
    let interfaceDef += ['/**',' * TODO: Docs',' * @interface']
    if interface["visibility"] != 'public'
        let interfaceDef += [' * @'.interface["visibility"]]
    endif
    for parent in interface["parent"]
        let interfaceDef += [' * @extends {'.parent.'}']
        if (g:GoogleClosureAutoRequire)
            call GoogleClosure_JS_Require(parent)
        endif
    endfor
    let interfaceDef += [' */']
    let interfaceDef += [GoogleClosure_JS_GetCurrentPackage().'.'.interface["name"].' = function() {};']
    call GoogleClosure_InsertLines(interfaceDef)
endfunction

function! GoogleClosure_JS_GetCurrentDefLineIndex()
    let prevousDevFound = 0
    let lineIndex = line('.')
    while !prevousDevFound && lineIndex > 0
        let lineContent = getline(lineIndex)
        if lineContent =~ '* @\(constructor\|interface\)'
            let prevousDevFound = 1
            break
        endif
        let lineIndex -= 1
    endwhile
    if !prevousDevFound
        throw 'Can''t find @class or @interface before current line'
    endif
    return lineIndex
endfunction

function! GoogleClosure_JS_IsInterface()
    let lineIndex = GoogleClosure_JS_GetCurrentDefLineIndex()
    let lineContent = getline(lineIndex)
    return lineContent =~ 'interface'
endfunction

function! GoogleClosure_JS_GetCurrentClass()
    let lineIndex = GoogleClosure_JS_GetCurrentDefLineIndex()
    let classFunctionFound = 0
    let currentLine = line('.')
    while !classFunctionFound && lineIndex <= currentLine
        let lineContent = getline(lineIndex)
        if lineContent =~ ' = function('
            let classFunctionFound = 1
            break
        endif
        let lineIndex += 1
    endwhile
    if !classFunctionFound
        throw 'Can''t find constructor'
    endif
    let className = matchlist(lineContent,'\([^ =]\+\) = function')[1]
    if className == ''
        throw 'Can''t find class'
    endif
    return className
endfunction

function! GoogleClosure_JS_GetType(type, default)
    let res = substitute(a:type,'[ :]\+','','g')
    if res == '' || tolower(res) == 'void'
        let res = a:default
    elseif tolower(res) == 'string' || tolower(res) == 'boolean' || tolower(res) == 'number'
        let res = tolower(res)
    endif
    return res
endfunction

function! GoogleClosure_JS_ParseMethod(methodDef)
    let res = {}
    let methodInfo = matchlist(a:methodDef,'\(static\|public\|private\|protected\|abstract\)\?[ ]\?\(private\|public\|protected\|static\|abstract\)\?[ ]*\([^($:]\+\)\(([^)]*)\)\?\(:[a-zA-Z0-9_\.]*\)\?')
    if methodInfo[0] == ''
        throw 'Invalid method signature'
    endif
    let res["interface"] = GoogleClosure_JS_IsInterface()
    let res["static"] = methodInfo[1] == 'static' || methodInfo[2] == 'static'
    let res["abstract"] = methodInfo[1] == 'abstract' || methodInfo[2] == 'abstract'
    let res["visibility"] = ''
    let res["name"] = methodInfo[3]
    if methodInfo[2] != 'static' && methodInfo[2] != 'abstract' && methodInfo[2] != ''
        let res["visibility"] = methodInfo[2]
    else
        if methodInfo[1] != 'static' && methodInfo[1] != 'abstract' && methodInfo[1] != ''
            let res["visibility"] = methodInfo[1]
        else
            if stridx(res["name"],'_') == strlen(res["name"]) - 1
                let res["visibility"] = res["abstract"] ? 'protected' : 'private'
            else
                let res["visibility"] = 'public'
            endif
        endif
    endif

    if res["interface"] && res["static"]
        throw 'Interface method cannot be static'
    endif

    let res["name"] = GoogleClosure_JS_CheckName(res["name"], res["visibility"])

    let args = methodInfo[4]
    if stridx(args,'(') == 0
        let args = strpart(args, 1)
    endif
    if stridx(args,')') == (strlen(args)-1)
        let args = strpart(args, 0, strlen(args)-1)
    endif
    let res["args"] = []
    if (args != '')
        " argument definition: name[:type][ = default]
        for argDef in split(args, ';')
            let argInfo = matchlist(argDef, '\([^:=]\+\):\?\([^=$]*\)\?[ =]*\(.*\)\?')
            if argInfo[0] == ''
                continue
            endif
            let argument = {}
            let argument["name"] = substitute(argInfo[1],'[ ]\+','','g')
            let argument["type"] = GoogleClosure_JS_GetType(argInfo[2], '*')
            let argument["default"] = substitute(argInfo[3],'[ ]\+','','g')
            if argument["default"] != '' && stridx(argument["name"], 'opt_') != 0
                let argument["name"] = 'opt_'.argument["name"]
            endif
            call add(res["args"], argument)
        endfor
    endif

    let res["return"] = GoogleClosure_JS_GetType(methodInfo[5], '')
    return res
endfunction

" Signature:
" [static ][public|private|protected] methodName[(argName:argType; anotherArgName: argType)][:returnType]
" Examples:
" testMethod - public method without args and return
" private testMethod - private method without args and return
" static myStaticMethod - public static method without args and return
" static protected myStaticProtectedTestMethod - protected static method without args and return
" testMethod(p1:number; p2:boolean; p3:my.ClassName):number
function! GoogleClosure_JS_CreateMethod(methodDef)

    let method = GoogleClosure_JS_ParseMethod(a:methodDef)

    let methodDocs = ['/**', ' * TODO: Write docs']
    if method["abstract"]
        let methodDocs += [' * @abstract']
    endif

    let methodStr = GoogleClosure_JS_GetCurrentClass()
    let methodCode = []
    if method["static"]
        let methodDocs += [' * @static']
        let methodStr .= '.'.method["name"]
    else
        let methodStr .= '.prototype.'.method["name"]
    endif
    let methodStr .= ' = function('

    if method["visibility"] != 'public'
        let methodDocs += [' * @'.method["visibility"]]
    endif

    let methodArgsString = []
    for arg in method["args"]
        let argDef = '@param {'.arg["type"]
        if arg["default"] != ''
            let argDef .= '='
            if !method["abstract"] && !method["interface"]
                let methodCode += ['    if (goog.isUndefined('.arg["name"].')) '.arg["name"].' = '.arg["default"].';']
            endif
        endif
        let argDef .= '} '.arg["name"]
        let methodDocs += [' * '.argDef]
        let methodArgsString += [arg["name"]]
    endfor
    let methodStr .= join(methodArgsString,',').') {'
    if method["abstract"]
        let methodCode += ['    goog.abstractMethod();']
    elseif method["interface"]
        let methodStr .= '};'
    else
        let methodCode += ['    throw new Error(''Not implemented'');']
    endif
    
    if method["return"] != ''
        let methodDocs += [' * @return {'.method["return"].'}']
    endif
    let methodDocs += [' */']

    let code = methodDocs
    let code += [methodStr]
    let code += methodCode
    if !method["interface"]
        let code += ['};']
    endif
    call GoogleClosure_InsertLines(code)
endfunction

function! GoogleClosure_JS_GetUpperCaseName(name)
    let res = ''
    let index = 0
    while index < strlen(a:name)
        let c = strpart(a:name, index, 1)
        if toupper(c) ==# c
            let res .= '_'
        endif
        let res .= toupper(c)
        let index += 1
    endwhile
    return res
endfunction

" private|public enumName:enumType{item1, item2, item3)
function! GoogleClosure_JS_ParseEnumDef(enumDef)
    let enumInfo = matchlist(a:enumDef, '\(private\|public\)\?[ ]*\([^ :{($]\+\):\?\([^({]\+\)\?[{( ]\?\([^})]\+\)\?')

    if len(enumInfo) == 0 || enumInfo[0] == ''
        throw 'Invalid enum definition'
    endif
    let res = {}
    let res["visibility"] = (enumInfo[1] == '') ? "public" : enumInfo[1]

    let res["name"] = GoogleClosure_JS_CheckName(enumInfo[2], res["visibility"])
    let res["type"] = (enumInfo[3] == '') ? 'number' : GoogleClosure_JS_GetType(enumInfo[3], 'number')
    let res["items"] = []
    let index = 0
    if enumInfo[4] != ''
        let items = split(enumInfo[4],'[ :,;]\+')
        for enumItem in items
            let item = {}
            let item['name'] = toupper(enumItem)
            let item['value'] = enumItem
            if res["type"] == "number"
                let item['value'] = index
                let index += 1
            elseif res["type"] == 'string'
                let item['value'] = ''''.item['value'].''''
            endif
            call add(res["items"], item)
        endfor
    endif

    return res
endfunction

function! GoogleClosure_JS_CreateEnum(enumDef)
    let enum = GoogleClosure_JS_ParseEnumDef(a:enumDef)

    let enumDef  = ['//------------------------------------------------------------------------------']
    let enumDef += ['//','//        '.enum["name"].' enum','//']
    let enumDef += ['//------------------------------------------------------------------------------']
    let enumDef += ['/**',' * TODO: Docs',' * @enum {'.enum["type"].'}']
    if enum["visibility"] != 'public'
        let enumDef += [' * @'.enum["visibility"]]
    endif
    let enumDef += [GoogleClosure_JS_GetCurrentPackage().'.'.enum["name"].' = {']
    if len(enum["items"]) == 0
        let enumDef += ['    ']
    else
        let index = 0
        for item in enum['items']
            let itemStr = '    '.item["name"].': '.item["value"]
            if index != len(enum['items'])-1
                let itemStr .= ','
            endif
            let enumDef += [itemStr]
            let index += 1
        endfor
    endif
    let enumDef += ['};']
    call GoogleClosure_InsertLines(enumDef)
endfunction

function! GoogleClosure_JS_ParseProp(propDef)
    let propInfo = matchlist(a:propDef, '\(public\|static\|protected\|private\)\?[ ]*\(public\|static\|protected\|private\)\?[ ]*\([^:]\+\)[: ]*\([^ =]*\)[ =]*\(.*\)')
    if len(propInfo) == 0 || propInfo[0] == ''
        throw 'Invalid prop def'
    endif

    let res = {}
    let res['name'] = propInfo[3]
    let res['static'] = propInfo[1] == 'static' || propInfo[2] == 'static'
    if propInfo[1] != 'static' && propInfo[1] != ''
        let res['visibility'] = propInfo[1]
    elseif propInfo[2] != 'static' && propInfo[2] != ''
        let res['visibility'] = propInfo[2]
    else
        let res["visibility"] = (stridx(res["name"],'_') == strlen(res["name"]) - 1) ? 'private' : 'public'
    endif
    let res["name"] = GoogleClosure_JS_CheckName(res["name"], res["visibility"])
    let res["type"] = GoogleClosure_JS_GetType(propInfo[4], '*')
    let res["default"] = propInfo[5]
    if res["default"] == ''
        let res["default"] = res["type"] == 'number' ? 'NaN' : 'null'
    endif

    return res
endfunction

function! GoogleClosure_JS_CreateProp(propDef)

    let interface = GoogleClosure_JS_IsInterface()
    let prop = GoogleClosure_JS_ParseProp(a:propDef)
    let code = []
"    let code += ["//------------------------------------------------------------------------------"]
"    let code += ["//    ".prop['name']]
"    let code += ["//------------------------------------------------------------------------------"]
    let code += ['/**',' * TODO: Write docs.']

    if prop["static"]
        let code += [' * @static']
    endif

    if prop["visibility"] != 'public'
        let code += [' * @'.prop['visibility']]
    endif

    let class = GoogleClosure_JS_GetCurrentClass()

    let code += [' * @type {'.prop['type'].'}']
    let code += [' */']
    let srcString = class.'.'
    if !prop["static"]
        let srcString .= 'prototype.'
    endif

    let code += [srcString.prop['name'].' = '.prop['default'].';']

    call GoogleClosure_InsertLines(code)
endfunction

function! GoogleClosure_JS_CreateGetSet(get, set)
    let content = getline(line('.'))
    let class = GoogleClosure_JS_GetCurrentClass()
    let classForSearch = substitute(class,'\.','\\\.','g')
    if !(content =~ classForSearch.'\.\(prototype\.\)\?[^ =]\+[ ]*=[^;]\+;')
        echo 'Can''t find prop'
    endif
    
    let static = !(content =~ '\.prototype\.')

    let typeIndex = line('.')
    let type = ''
    while typeIndex > 0 && type == ''
        if getline(typeIndex) =~ ' \* @type {[^}]\+}'
            let type = matchlist(getline(typeIndex), ' \* @type {\([^}]\+\)}')[1]
        endif
        let typeIndex -= 1
    endwhile
    if type == ''
        throw 'Can''t find @type for prop'
    endif

    let name = matchlist(content, classForSearch.'\.\(prototype\.\)\?\([^ =]\+\)')[2]
    let realName = name
    if strridx(name,'_') == strlen(name) - 1
        let name = strpart(name, 0, strlen(name) - 1)
    endif
    let name = toupper(strpart(name, 0, 1)).strpart(name, 1)

    let code = []
    if a:get
        let code += ['/**']
        if static
            let code += [' * @static']
        endif
        let code += [' * @return {'.type.'}']
        let code += [' */']
        let code += [class.(static ? '' : '.prototype').'.get'.name.' = function() {']
        let code += ['    return '.(static ? class : 'this').'.'.realName.';']
        let code += ['};']
        if a:set
            let code += ['']
        endif
    endif

    if a:set
        let code += ['/**']
        if static
            let code += [' * @static']
        endif
        let code += [' * @param value {'.type.'}']
        let code += [' */']
        let code += [class.(static ? '' : '.prototype').'.set'.name.' = function(value) {']
        let code += ['    '.(static ? class : 'this').'.'.realName.' = value;']
        let code += ['};']
    endif

    call GoogleClosure_InsertLinesTo(code, line('.')+1,1)

endfunction

function! GoogleClosure_JS_CreateFromString(src)
    if (a:src =~ 'function[ ]\+')
        call GoogleClosure_JS_CreateMethod(substitute(a:src, 'function[ ]\+', '', 'g'))
    elseif (a:src =~ 'var[ ]\+')
        call GoogleClosure_JS_CreateProp(substitute(a:src, 'var[ ]\+', '', 'g'))
    endif
endfunction

function! GoogleClosure_OpenPackage(packageName)
    if g:GoogleClosureDeps == ''
        echo 'Please specify g:GoogleClosureDeps'
        return
    endif
    let content = readfile(g:GoogleClosureDeps)

    let pattern = 'goog\.addDependency("[^"]\+", \['''.a:packageName.'''\]'
    let index = match(content, pattern)
    if index == -1
        echo 'Can''t find '.a:packageName.' in deps.js'
        return
    endif

    let filePattern = 'goog\.addDependency("\([^"]\+\)", \['''.a:packageName.'''\]'
    let res = matchlist(content[index], filePattern)
    if len(res) == 0 || res[1] == ''
        echo 'Can''t parse deps.js'
        return
    endif

    let path = strpart(g:GoogleClosureDeps, 0, stridx(g:GoogleClosureDeps, '/deps.js'))
    let path .= '/'.res[1]

    execute "e ".path
endfunction

command! GoogleClosureCreateTestSuite :call GoogleClosure_MakeTest()
command! GoogleClosureCalcDeps :call GoogleClosure_CalcDeps()

command! -nargs=1 JSInterface :call GoogleClosure_JS_CreateInterface(<q-args>)
command! -nargs=1 JSClass :call GoogleClosure_JS_CreateClass(<q-args>)
command! -nargs=1 JSMethod :call GoogleClosure_JS_CreateMethod(<q-args>)
command! -nargs=1 JSEnum :call GoogleClosure_JS_CreateEnum(<q-args>)
command! -nargs=1 JSRequire :call GoogleClosure_JS_RequirePackage(<q-args>)
command! -nargs=1 JSProp :call GoogleClosure_JS_CreateProp(<q-args>)
command! JSGet :call GoogleClosure_JS_CreateGetSet(1, 0)
command! JSSet :call GoogleClosure_JS_CreateGetSet(0, 1)
command! JSGetSet :call GoogleClosure_JS_CreateGetSet(1, 1)
command! -nargs=1 JS :call GoogleClosure_JS_CreateFromString(<q-args>)
command! -nargs=1 JSPackage :call GoogleClosure_OpenPackage(<q-args>)
