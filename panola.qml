
//=============================================================================
//  MuseScore
//  Music Composition & Notation
//
//  Panola generation plugin
//
//  Copyright (C) 2012 Werner Schweer
//  Copyright (C) 2013 - 2020 Joachim Schmitz
//  Copyright (C) 2014 Jörn Eichler
//  Copyright (C) 2020 Johan Temmerman
//  Copyright (C) 2022 Stefaan Himpe
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
   
   // initStaffToPartIdx sets up a lookup table to convert staff index to part index
   // e.g. a piano part consists of a single part, but which has two staffs
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
   
   // calculateMeasures sets up a lookup table to convert ticks to measure numbers
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
   
   // tickToMeasure converts a tick value to a measure number
   // this only works if calculateMeasures has been executed before
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
   
   // getPartNameFromPartIndex converts the part number to a part (long) name
   // the staff idx is used as suffix (e.g. a single piano part consists of two staffs)
   function getPartNameFromPartIndex(partidx, staffidx) {
      if (curScore.parts[partidx] != null) {
         var candidatePartName = curScore.parts[partidx].longName.toLowerCase().replace(/ /g, "_").replace(/[^a-zA-Z0-9_]+/g, "")
         if (candidatePartName == null || candidatePartName == ""){
            candidatePartName = "part"
         }
         return candidatePartName + "_" + (parseInt(staffidx) + 1)          
      }
   }
   
   // panolaDuration creates a panola duration string from a musescore duration object
   function panolaDuration(duration) {
      var dur = "";
      dur += duration.denominator;
      if (duration.numerator != 1)
         dur +=   "*" + duration.numerator;
      return dur;
   }
   
   // panolaAccumulatedDuration creates a panola duration string from a list [duration numerator, duration denominator]
   // such lists are maintained while traversing the score as a way to handle ties (panola doesn't have a tie concept, so durations must be accumulated)
   function panolaAccumulatedDuration(duration_numden) {
      var dur = "";
      dur += duration_numden[1];
      if (duration_numden[0] != 1)
         dur +=   "*" + duration_numden[0];
      return dur;
   }
   
   // this function checks if the current tick belongs to a new measure (compared to the previous check)
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
   
   // this function calculates the greatest common divisor between two numbers
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
   
   // addDuration adds two fractions together. Both fractions are represented as [numerator, denominator].
   // addDuration can be used to add durations while handling tied notes
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
   
   // multiplyDuration multiplies two durations together
   // this is used while handling tuplets
   function multiplyDuration(duration_numden1, multiplier_numden)
   {
      var num1 = duration_numden1[0];
      var den1 = duration_numden1[1];
      var num2 = multiplier_numden[0];
      var den2 = multiplier_numden[1];
      var num3 = num1*num2;
      var den3 = den1*den2;
      var simplification = gcd_two_numbers(num3, den3);
      return [num3 / simplification, den3 / simplification];
   }
   
   // function to reset some internal state maintained while tracking how long a note in the current voice is tied
   function resetTieOngoing()
   {
      tieOnGoing = ({});
      for (var note=0; note<128; note++)
      {
         accumulatedDuration[note] = [0,1];
      }
   }
   
   // function to update some internal state maintained while tracking how long a note in the current voice is tied
   function updateTieOngoing(note, duration_numden, tick) 
   {
      if (note.tieForward != null)
      {
         //console.log("found a tie for note " + note.pitch + " in measure " + tickToMeasure(tick));
         tieOnGoing[note.pitch] = true;
         accumulatedDuration[note.pitch] = addDuration(accumulatedDuration[note.pitch], duration_numden);
         
      } else 
      {
         //if (tieOnGoing[note.pitch] == true) 
         //{
         //   console.log("ending tie for note " + note.pitch + " in measure " + tickToMeasure(tick));  
         //}
         tieOnGoing[note.pitch] = false;
         accumulatedDuration[note.pitch] = addDuration(accumulatedDuration[note.pitch], duration_numden);
      }
   }
   
   // function that returns true if the current segment,track,tick has a dynamics indication
   function hasDynamics(segment, track, tick)
   {
      var annotations = segment.annotations;
      for (var i = 0; i < annotations.length; ++i) {
         var a = annotations[i];
         if (a.track != track)
               continue;
         if (a.name == "Dynamic" && a.parent.tick == tick) {
            if (a.text.includes("<sym>dynamicForte</sym>") || a.text.includes("<sym>dynamicPiano</sym>") || a.text.includes("<sym>dynamicMezzo</sym>"))
            {
               return true;
            }
         }
      }
      return false;
   }
   
   // function that returns the dynamics indication found at the current segment,track,tick in panola notation
   function extractDynamics(segment, track, tick)
   {
      var annotations = segment.annotations;
      for (var i = 0; i < annotations.length; ++i) {
         var a = annotations[i];
         if (a.track != track)
               continue;
         if (a.name == "Dynamic" && a.parent.tick == tick) {
            var retval = 
               "@vol[" +
               a.text.split("<sym>dynamicForte</sym>").join("f")
                     .split("<sym>dynamicPiano</sym>").join("p")
                     .split("<sym>dynamicMezzo</sym>p").join("mp")
                     .split("<sym>dynamicMezzo</sym>f").join("mf")
               + "]";
            //console.log("retval ", retval);
            return retval;
         }
      }
      return "";
   }
   
   // function that generates a panola chord string taking into account the musescore chord, duration, tuplets, dynamics, etc
   function panolaChord(notes, duration, tick, isRest, tuplet_multiplier, dynamics) 
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
            
            updateTieOngoing(notes[i], multiplyDuration([duration.numerator, duration.denominator], tuplet_multiplier), tick);
            
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
               chord += (Math.floor(notes[i].pitch / 12) - 1);
               
            }
            
            if (i == 0 && (tieOnGoing[notes[i].pitch] == false)) {            
               chord += "_";
               chord += panolaAccumulatedDuration(accumulatedDuration[notes[i].pitch]);
               accumulatedDuration[notes[i].pitch] = [0,1];
               if (dynamics != "")
               {
                  chord += dynamics;
               }
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
   
   // element that can save stuff to file - filename hardcoded for now
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
      fullText += "// Panola generated from musescore using plugin\n";
      fullText += "// warning: notes that are tied over from a previous measure are added in the next measure instead\n";
      fullText += "// warning: partially tied chords will not export correctly\n";
      fullText += "// warning: grace notes currently are not supported\n";
      fullText += "var dynPPPPP = 10.0/127;\n";
      fullText += "var dynPPPP = 20.0/127;\n";
      fullText += "var dynPPP = 30.0/127;\n";
      fullText += "var dynPP = 40.0/127;\n";
      fullText += "var dynP = 50.0/127;\n";
      fullText += "var dynMP = 60.0/127;\n";
      fullText += "var dynMF = 70.0/127;\n";
      fullText += "var dynF = 80.0/127;\n";
      fullText += "var dynFF = 90.0/127;\n";
      fullText += "var dynFFF = 100.0/127;\n";
      fullText += "var dynFFFF = 110.0/127;\n";
      fullText += "var dynFFFFF = 120.0/127;\n";
      
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
                  var tuplet_multiplier = [1,1];
                  var tuplet = cursor.element.tuplet;
                  if (tuplet != null) 
                  {
                     var actualNotes = tuplet.actualNotes;
                     var normalNotes = tuplet.normalNotes;
                     tuplet_multiplier = [normalNotes, actualNotes];
                  }
                  var trackIdx = staff*4 + voice;
                  var dynamics = "";
                  if (hasDynamics(cursor.segment, trackIdx, cursor.tick))
                     dynamics = extractDynamics(cursor.segment, trackIdx, cursor.tick);
                  var tick = cursor.tick;
                  text += panolaChord(notes, duration, tick, false, tuplet_multiplier, dynamics);
               } 
               else if (cursor.element && cursor.element.type === Element.REST) {
                  var notes = cursor.element.notes;
                  var duration = cursor.element.duration;
                  var tuplet_multiplier = [1,1];
                  var tuplet = cursor.element.tuplet;
                  if (tuplet != null) 
                  {
                     var actualNotes = tuplet.actualNotes;
                     var normalNotes = tuplet.normalNotes;
                     tuplet_multiplier = [normalNotes, actualNotes];
                  }
                  var tick = cursor.tick;
                  text += panolaChord(notes, duration, tick, true, tuplet_multiplier, "");
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
               fullText += "\n].join(\" \")";
               fullText += ".replace(\"[ppppp]\", \"[\" ++ dynPPPPP ++ \"]\")";
               fullText += ".replace(\"[pppp]\", \"[\" ++ dynPPPP ++ \"]\")";
               fullText += ".replace(\"[ppp]\", \"[\" ++ dynPPP ++ \"]\")";
               fullText += ".replace(\"[pp]\", \"[\" ++ dynPP ++ \"]\")";
               fullText += ".replace(\"[p]\", \"[\" ++ dynP ++ \"]\")";
               fullText += ".replace(\"[mp]\", \"[\" ++ dynMP ++ \"]\")";
               fullText += ".replace(\"[mf]\", \"[\" ++ dynMF ++ \"]\")";
               fullText += ".replace(\"[f]\", \"[\" ++ dynF ++ \"]\")";
               fullText += ".replace(\"[ff]\", \"[\" ++ dynFF ++ \"]\")";
               fullText += ".replace(\"[fff]\", \"[\" ++ dynFFF ++ \"]\")";
               fullText += ".replace(\"[ffff]\", \"[\" ++ dynFFFF ++ \"]\")";
               fullText += ".replace(\"[fffff]\", \"[\" ++ dynFFFFF ++ \"]\")";
               fullText += ");\n";
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

