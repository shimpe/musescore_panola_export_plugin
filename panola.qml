
//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Note Names Plugin
//
//  Copyright (C) 2012 Werner Schweer
//  Copyright (C) 2013 - 2020 Joachim Schmitz
//  Copyright (C) 2014 Jörn Eichler
//  Copyright (C) 2020 Johan Temmerman
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2
//  as published by the Free Software Foundation and appearing in
//  the file LICENCE.GPL
//=============================================================================

import QtQuick 2.2
import MuseScore 3.0
import FileIO 3.0

MuseScore {
   version: "0.0.1"
   description: qsTr("This plugin generates a panola string per staff and per measure")
   menuPath: "Plugins.Panola.Generate"
   
   property	var arrMeasures: [];
   property var mapStaffToPartIndex : ({}); // must use round brackets otherwise it is parsed as a binding expression
   property var previousMeasureNo : null;
   property var tieOnGoing : ({});
   property var accumulatedDuration : ({});
   
   function initStaffToPartIdx() {
      var staffNo = 0;
      for (var p=0; p < curScore.parts.length; p++) {
         var noOfStaves = (curScore.parts[p].endTrack - curScore.parts[p].startTrack)/4;
         for (var s=0; s < noOfStaves; s++) {
            mapStaffToPartIndex[staffNo] = p;
            staffNo = staffNo + 1;
         } 
      }  
   }
   
   function calculateMeasures() {
      var cursor = curScore.newCursor()
      for (var trackIdx = 0; trackIdx < curScore.ntracks; trackIdx++) {
         cursor.track = trackIdx
         cursor.rewind(0)
         while (cursor.segment) {
            if (arrMeasures.indexOf(cursor.tick) == -1)
               arrMeasures.push(cursor.tick)
               cursor.nextMeasure()
         }
      }
      arrMeasures.sort(function(a, b) {
         return a - b
      })
   }
   
   function tickToMeasure(tick) {
      // suppose that arrMeasures has been initialized already
      for (var index=0; index < arrMeasures.length-1; ++index) {
         if (arrMeasures[index] == tick) {
            return index+1;
         }
         if (arrMeasures[index+1] == tick) {
            return index+2;
         }
         if (arrMeasures[index] < tick && arrMeasures[index+1] > tick)
         {
            return index+1;
         }
      }
      return arrMeasures.length;
   }
   
   function getPartNameFromPartIndex(partidx, staffidx) {
      if (curScore.parts[partidx] != null) {
         var candidatePartName = curScore.parts[partidx].longName.toLowerCase().replace(/ /g, "_").replace(/[^a-zA-Z0-9_]+/g, "")
         if (candidatePartName == null || candidatePartName == ""){
            candidatePartName = "part"
         }
         return candidatePartName + "_" + (parseInt(staffidx) + 1)          
      }
   }
   
   function panolaDuration(duration) {
      var dur = "";
      dur += duration.denominator;
      if (duration.numerator != 1)
         dur +=   "*" + duration.numerator;
      return dur;
   }
   
   function panolaAccumulatedDuration(duration_numden) {
      var dur = "";
      dur += duration_numden[1];
      if (duration_numden[0] != 1)
         dur +=   "*" + duration_numden[0];
      return dur;
   }
   
   function measureSeparatorIfNeeded(tick)
   {
      var measureNo = tickToMeasure(tick);
      if (previousMeasureNo == null)
      {
         previousMeasureNo = measureNo;
         return '"';
      }
      if (measureNo != previousMeasureNo)
      {
         previousMeasureNo = measureNo;
         return '", // measure ' + (measureNo-1).toString() + '\n"';
      }
      return "";
   }
   
   function gcd_two_numbers(x, y) {
      if ((typeof x !== 'number') || (typeof y !== 'number')) 
         return false;
      x = Math.abs(x);
      y = Math.abs(y);
      while(y) {
         var t = y;
         y = x % y;
         x = t;
      }
      return x;
   }
   
   function addDuration(duration_numden1, duration_numden2)
   {
      var num1 = duration_numden1[0];
      var den1 = duration_numden1[1];
      var num2 = duration_numden2[0];
      var den2 = duration_numden2[1];
      var num3 = num1*den2 + num2*den1;
      var den3 = den1*den2;
      var simplification = gcd_two_numbers(num3, den3);
      return [num3 / simplification, den3 / simplification];
   }
   
   function resetTieOngoing()
   {
      tieOnGoing = ({});
      for (var note=0; note<128; note++)
      {
         accumulatedDuration[note] = [0,1];
      }
   }
   
   function updateTieOngoing(note, duration_numden, tick) 
   {
      if (note.tieForward != null)
      {
         console.log("found a tie for note " + note.pitch + " in measure " + tickToMeasure(tick));
         tieOnGoing[note.pitch] = true;
         accumulatedDuration[note.pitch] = addDuration(accumulatedDuration[note.pitch], duration_numden);
         
      } else 
      {
         if (tieOnGoing[note.pitch] == true) 
         {
            console.log("ending tie for note " + note.pitch + " in measure " + tickToMeasure(tick));  
         }
         tieOnGoing[note.pitch] = false;
         accumulatedDuration[note.pitch] = addDuration(accumulatedDuration[note.pitch], duration_numden);
      }
   }
   
   function panolaChord(notes, duration, tick, isRest) 
   {
      var chord = "";
      if (isRest) {
         
         chord += measureSeparatorIfNeeded(tick);
         chord += "r";
         chord += "_";
         chord += panolaDuration(duration);    
         
         chord += " ";
         
         resetTieOngoing();
         
      } else {
         
         for (var i=0; i < notes.length; i++) {
            
            if (typeof notes[i].tpc1 === "undefined") // like for grace notes ?!?
               return;
            
            updateTieOngoing(notes[i], [duration.numerator, duration.denominator], tick);
            
            chord += measureSeparatorIfNeeded(tick);
            
            if (i==0 && notes.length > 1 && (tieOnGoing[notes[i].pitch] == false))
            {
               chord += "<";
            }
            
            if (tieOnGoing[notes[i].pitch] == false)
            {
               switch(notes[i].tpc1) {
                  case -1:chord += "f--"; break;
                  case  0: chord += "c--"; break;
                  case  1: chord += "g--"; break;
                  case  2: chord += "d--"; break;
                  case  3: chord += "a--"; break;
                  case  4: chord += "e--"; break;
                  case  5: chord += "b--"; break;
                  case  6: chord += "f-"; break;
                  case  7: chord += "c-"; break;
                  
                  case  8: chord += "g-"; break;
                  case  9: chord += "d-"; break;
                  case 10: chord += "a-"; break;
                  case 11: chord += "e-"; break;
                  case 12: chord += "b-"; break;
                  case 13: chord += "f"; break;
                  case 14: chord += "c"; break;
                  case 15: chord += "g"; break;
                  case 16: chord += "d"; break;
                  case 17: chord += "a"; break;
                  case 18: chord += "e"; break;
                  case 19: chord += "b"; break;
                  
                  case 20: chord += "f#"; break;
                  case 21: chord += "c#"; break;
                  case 22: chord += "g#"; break;
                  case 23: chord += "d#"; break;
                  case 24: chord += "a#"; break;
                  case 25: chord += "e#"; break;
                  case 26: chord += "b#"; break;
                  case 27: chord += "f##"; break;
                  case 28: chord += "c##"; break;
                  case 29: chord += "g##"; break;
                  case 30: chord += "d##"; break;
                  case 31: chord += "a##"; break;
                  case 32: chord += "e##"; break;
                  case 33: chord += "b##";break;
                  default: text.text = qsTr("?")   + text.text; break;
               }
               // octave, middle C being C4
               chord += (Math.floor(notes[i].pitch / 12) - 1)
               
            }
            
            if (i == 0 && (tieOnGoing[notes[i].pitch] == false)) {            
               chord += "_";
               chord += panolaAccumulatedDuration(accumulatedDuration[notes[i].pitch]);
               accumulatedDuration[notes[i].pitch] = [0,1];
            }
            
            if (i==(notes.length-1) && notes.length >1 && (tieOnGoing[notes[i].pitch] == false))
            {
               chord += ">"
            }                       
            
            if (tieOnGoing[notes[i].pitch] == false) {
               chord += " ";    
            }
         }  
      }
      return chord;
   }
   
   FileIO {
      id: resultFile
      source: homePath() + "/panola.txt";
   }
   
   onRun: {
      var cursor = curScore.newCursor();
      var startStaff;
      var endStaff;
      var endTick;
      
      var fullText = "";
      
      initStaffToPartIdx();
      calculateMeasures();
      
      var fullScore = false;
      cursor.rewind(1);
      if (!cursor.segment) { // no selection
         fullScore = true;
         startStaff = 0; // start with 1st staff
         endStaff  = curScore.nstaves - 1; // and end with last
      } else {
         startStaff = cursor.staffIdx;
         cursor.rewind(2);
         if (cursor.tick === 0) {
            // this happens when the selection includes
            // the last measure of the score.
            // rewind(2) goes behind the last segment (where
            // there's none) and sets tick=0
            endTick = curScore.lastSegment.tick + 1;
         } else {
            endTick = cursor.tick;
         }
         endStaff = cursor.staffIdx;
      }
      
      for (var staff = startStaff; staff <= endStaff; staff++) {
         for (var voice = 0; voice < 4; voice++) {
            var text = "";
            previousMeasureNo = null;
            cursor.rewind(1); // beginning of selection
            cursor.voice    = voice;
            cursor.staffIdx = staff;
            
            resetTieOngoing();
            
            if (fullScore)  {// no selection
               cursor.rewind(0); // beginning of score
            }
            while (cursor.segment && (fullScore || cursor.tick < endTick)) {
               if (cursor.element && cursor.element.type === Element.CHORD) {
                  
                  // Now handle the note names on the main chord...
                  var notes = cursor.element.notes;
                  var duration = cursor.element.duration;
                  var tick = cursor.tick;
                  text += panolaChord(notes, duration, tick, false);
               } 
               else if (cursor.element && cursor.element.type === Element.REST) {
                  var notes = cursor.element.notes;
                  var duration = cursor.element.duration;
                  var tick = cursor.tick;
                  text += panolaChord(notes, duration, tick, true);
               }
               else // end if CHORD 
               {
                  console.log("unhandled cursor.element.type: ", cursor.element.type);
               }
               cursor.next();
            } // end while segment
            
            if (text != "") {
               console.log("Exporting Staff= ", getPartNameFromPartIndex(mapStaffToPartIndex[staff], staff), " Voice= ", voice);
               //console.log('"' + text + '"');
               fullText += "\nvar " + getPartNameFromPartIndex(mapStaffToPartIndex[staff], staff) + " = Panola([\n" + text + "\"";
               fullText += " // measure " + previousMeasureNo;
               fullText += "\n].join(\" \"));\n";
            }
         } // end for voice
      } // end for staff
      
      if (fullText != "") 
      {
         resultFile.write('(\n' + fullText + ')\n');  
      }
      
      Qt.quit();
   } // end onRun
}

