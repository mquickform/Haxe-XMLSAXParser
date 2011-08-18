/*
 * Copyright (c) 2011, Marcus Bergstrom and The haXe Project Contributors
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE HAXE PROJECT CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

package net.quickform.utils;

import haxe.io.StringInput;
import haxe.io.Error;
import haxe.io.Eof;

typedef StackItem = {
	var tag:String;
	var tagFull:String;
	var elements:Int;
	var ns:String;
}

typedef AttrItem = {
	var name:String;
	var value:String;
	var ns:String;
}

class XMLSAXParser {
	
	// http://www.asciitable.com/
	private static inline var CHAR_LESSTHAN:Int = 60; // "<"
	private static inline var CHAR_MORETHAN:Int = 62; // ">"
	private static inline var CHAR_SLASH:Int = 47; // "/"
	private static inline var CHAR_SPACE:Int = 32; // " "
	private static inline var CHAR_COLON:Int = 58; // ":"
	private static inline var CHAR_QUOTE:Int = 39; // "'"
	private static inline var CHAR_DOUBLEQUOTE:Int = 34; // """
	private static inline var CHAR_EQUALS:Int = 61; // "="
	private static inline var CHAR_EXCLAMATION:Int = 33; // "!"
	private static inline var CHAR_QUESTION:Int = 63; // "?"
	private static inline var CHAR_HYPHEN:Int = 45; // "-"
	
	private static inline var CONTINUE_PARSING:Bool = true;
	private static inline var SKIP_TAG:Bool = false;
	
	var buf:StringInput;
	var stack:Array<String>;
	var defaultNamespace:String;
	var namespaces:Hash<String>;
	var onFinished:Void->Void;
	public var onStartTag:String->String->Bool;
	public var onEndTag:String->String->Void;
	public var onData:String->Void;
	public var onProlog:String->Void;
	public var onComment:String->Void;
	public var onAttr:String->String->String->Void;
	
	public function new(xml:String) {
		buf = new StringInput(xml);
		stack = new Array();
		namespaces = new Hash();
		defaultNamespace = "";
	}
	
	public function start():Void {
		var char:Int = -1;
		// Entry.
		var startParsingTag:Bool = true;
		var parsingTag:Bool = false;
		var parsingEntryName:Bool = false;
		var entryName:StringBuf = new StringBuf();
		var entryNameToBroadcast:String = "";
		var namespaceToBroadcast:String = "";
		// Attributes.
		var parsingAttr:Bool = false;
		var attrName:StringBuf = null;
		var attrWrapperChar:Int = -1;
		// Content.
		var content:StringBuf = new StringBuf();
		
		var skipRecordingThisChar:Bool = false;
		var readNextByte:Bool = true;
		// We'll use a stack to keep track of current parse level,
		// and to see if a tag is a PCData or a proper element.
		var stack:Array<StackItem> = new Array();
		var stackLen:Int = 0;
		
		var attributesInTag:Array<AttrItem> = new Array();
		
		buf.readUntil(CHAR_LESSTHAN);
		
		try {
			while(true) {
				if (readNextByte) char = buf.readByte();
				readNextByte = true;
				
				skipRecordingThisChar = false;
			
				// ========================
				// FLOW ALTERING STATEMENTS.
				// ========================
				if (startParsingTag) {
					startParsingTag = false;
					
					if (char == CHAR_SLASH) {
						if (onData != null && stackLen > 0 && stack[stackLen-1].elements == 0)
							onData(content.toString());
													
						var stackTmp:StackItem = stack.pop();
						stackLen--;
						
						var foundEndTag:String = buf.readUntil(CHAR_MORETHAN);
						if (foundEndTag != stackTmp.tagFull)
							throw("End Tag Mismatch: Found " +foundEndTag+", should have been: "+stackTmp.tagFull);
												
						// List attributes.
						while(attributesInTag.length > 0) {
							var tmpAttrItem:AttrItem = attributesInTag.shift();
							if (onAttr != null)
								onAttr(tmpAttrItem.name, tmpAttrItem.value, (tmpAttrItem.ns == "") ? namespaceToBroadcast : namespaces.get(tmpAttrItem.ns));
						}				
						if (onEndTag != null) onEndTag(stackTmp.tag, stackTmp.ns);
					} else if (char == CHAR_EXCLAMATION) {
						// We assume this is a comment.
						if (buf.readString(2) == "--") {
							var comment:StringBuf = new StringBuf();
							var commentTmp:String = "";
							while(true) {
								comment.add(buf.readUntil(CHAR_HYPHEN));
								if ((commentTmp = buf.readString(2)) == "->") break;
							}
							if (onComment != null) onComment(comment.toString());
						} else {
							buf.readUntil(CHAR_MORETHAN);
						}
					} else if (char == CHAR_QUESTION) {
						// We assume this is a prolog.
						if (buf.readString(3) == "xml") {
							buf.readByte();
							var prolog:String = buf.readUntil(CHAR_QUESTION);
							buf.readByte();
							if (onProlog != null) onProlog(prolog);
						} else {
							buf.readUntil(CHAR_MORETHAN);
						}
					} else {
						attributesInTag = new Array();
						parsingTag = true;
						parsingEntryName = true;
						entryName = new StringBuf();
						parsingAttr = false;
					}
				}
				
				if (parsingTag) {

					skipRecordingThisChar = true;
										
					if ((char == CHAR_MORETHAN || char == CHAR_SLASH) && !parsingAttr) {
						// This is the end of the start tag,
						parsingTag = false;
						if (char == CHAR_MORETHAN) content = new StringBuf();
						
						var entryNameTmp = entryName.toString();
						var entryNameTmpPos:Int = entryNameTmp.indexOf(":");
						entryNameToBroadcast = entryNameTmp;
						namespaceToBroadcast = defaultNamespace;
						if (entryNameTmpPos > -1) {
							var nsTmp:String = entryNameTmp.substr(0,entryNameTmpPos);
							if (!namespaces.exists(nsTmp))
								throw("The namespace "+nsTmp+" has not been defined!");
							entryNameToBroadcast = entryNameTmp.substr(entryNameTmpPos+1);
							namespaceToBroadcast = namespaces.get(nsTmp);
						}

						var continueParsing:Bool = (onStartTag == null) ? false : onStartTag(entryNameToBroadcast, namespaceToBroadcast);

						if (stackLen > 0) stack[stackLen-1].elements++;
						if (char == CHAR_SLASH) {
							// it's also the end of the tag.
							// So don't push it to the stack.
							// Also list all the attributes.
							while(attributesInTag.length > 0) {
								var tmpAttrItem:AttrItem = attributesInTag.shift();
								if (onAttr != null) onAttr(tmpAttrItem.name, tmpAttrItem.value, (tmpAttrItem.ns == "") ? namespaceToBroadcast : namespaces.get(tmpAttrItem.ns));
							}
							if (onEndTag != null) onEndTag(entryNameToBroadcast, namespaceToBroadcast);
							buf.readByte();
						} else {
							if (!continueParsing) {
								while(true) {
									buf.readUntil(CHAR_LESSTHAN);
									if (buf.readByte() == CHAR_SLASH) {
										if (buf.readUntil(CHAR_MORETHAN) == entryNameTmp) {											
											if (onEndTag != null) onEndTag(entryNameToBroadcast, namespaceToBroadcast);
											parsingTag = false;
											parsingAttr = false;
											parsingEntryName = false;
											break;
										}
									}
								}
							} else {
								stack.push({tag: entryNameToBroadcast, tagFull: entryName.toString(), elements: 0, ns: namespaceToBroadcast});
								stackLen++;
								// Also list all the attributes.
								while(attributesInTag.length > 0) {
									var tmpAttrItem:AttrItem = attributesInTag.shift();
									if (onAttr != null) onAttr(tmpAttrItem.name, tmpAttrItem.value, (tmpAttrItem.ns == "") ? namespaceToBroadcast : namespaces.get(tmpAttrItem.ns));
								}
							}
						}
					}
					
					if (parsingEntryName) {
					
						if (char == CHAR_SPACE || char == CHAR_MORETHAN || char == CHAR_SLASH)
							parsingEntryName = false;
					
					} else if (parsingAttr) {
						if (char == CHAR_SLASH) {
							readNextByte = false;
							parsingAttr = false;
						} else if (char == CHAR_EQUALS) {
							parsingAttr = false;
							// Read attribute.
							attrWrapperChar = buf.readByte();
							var attrValue = buf.readUntil(attrWrapperChar);
							var attrNameTmp:String = attrName.toString();
							if (attrNameTmp == "xmlns") {
								defaultNamespace = attrValue;
								namespaces.set("", defaultNamespace);
							} else if (attrNameTmp.length > 6 && attrNameTmp.substr(0,5) == "xmlns") {
								namespaces.set(attrNameTmp.substr(6), attrValue);
							} else {
								var attrNameTmpIndex:Int = attrNameTmp.indexOf(":");
								if (attrNameTmpIndex == -1)
									attributesInTag.push({name: attrNameTmp, value: attrValue, ns: ""});
								else 
									attributesInTag.push({name: attrNameTmp.substr(attrNameTmpIndex+1), value: attrValue, ns: attrNameTmp.substr(0,attrNameTmpIndex)});									
							}
						}
					}

					if (char == CHAR_SPACE && !parsingEntryName && !parsingAttr) {
						parsingAttr = true;
						attrName = new StringBuf();					
					}							
				} else {
					if (char == CHAR_LESSTHAN) {
						startParsingTag = true;	
						skipRecordingThisChar = true;					
					}
				}


				// ====================
				// RECORDING STATEMENTS.
				// ====================
				if (parsingTag) {
					if (parsingEntryName && char != CHAR_SPACE)
						entryName.addChar(char);
					else if (parsingAttr && char != CHAR_SPACE)
						attrName.addChar(char);
				}
				
				// Don't allow storing content if the entry is not a text element.
				// Easiest way to find that out is to check the first char after the entry opening tag?
				
				if (!skipRecordingThisChar) content.addChar(char);

			}
		} catch(e:Eof) {
			if (stackLen == 0) {
				if (onFinished != null) onFinished();
			} else throw("Error while parsing unbalanced xml");
		} catch(e:Error) {
			throw("Error while parsing xml");
		}
	}
	
}