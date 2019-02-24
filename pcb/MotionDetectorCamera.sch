<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE eagle SYSTEM "eagle.dtd">
<eagle version="9.3.0">
<drawing>
<settings>
<setting alwaysvectorfont="no"/>
<setting verticaltext="up"/>
</settings>
<grid distance="0.1" unitdist="inch" unit="inch" style="lines" multiple="1" display="no" altdistance="0.01" altunitdist="inch" altunit="inch"/>
<layers>
<layer number="1" name="Top" color="4" fill="1" visible="no" active="no"/>
<layer number="16" name="Bottom" color="1" fill="1" visible="no" active="no"/>
<layer number="17" name="Pads" color="2" fill="1" visible="no" active="no"/>
<layer number="18" name="Vias" color="2" fill="1" visible="no" active="no"/>
<layer number="19" name="Unrouted" color="6" fill="1" visible="no" active="no"/>
<layer number="20" name="Dimension" color="24" fill="1" visible="no" active="no"/>
<layer number="21" name="tPlace" color="7" fill="1" visible="no" active="no"/>
<layer number="22" name="bPlace" color="7" fill="1" visible="no" active="no"/>
<layer number="23" name="tOrigins" color="15" fill="1" visible="no" active="no"/>
<layer number="24" name="bOrigins" color="15" fill="1" visible="no" active="no"/>
<layer number="25" name="tNames" color="7" fill="1" visible="no" active="no"/>
<layer number="26" name="bNames" color="7" fill="1" visible="no" active="no"/>
<layer number="27" name="tValues" color="7" fill="1" visible="no" active="no"/>
<layer number="28" name="bValues" color="7" fill="1" visible="no" active="no"/>
<layer number="29" name="tStop" color="7" fill="3" visible="no" active="no"/>
<layer number="30" name="bStop" color="7" fill="6" visible="no" active="no"/>
<layer number="31" name="tCream" color="7" fill="4" visible="no" active="no"/>
<layer number="32" name="bCream" color="7" fill="5" visible="no" active="no"/>
<layer number="33" name="tFinish" color="6" fill="3" visible="no" active="no"/>
<layer number="34" name="bFinish" color="6" fill="6" visible="no" active="no"/>
<layer number="35" name="tGlue" color="7" fill="4" visible="no" active="no"/>
<layer number="36" name="bGlue" color="7" fill="5" visible="no" active="no"/>
<layer number="37" name="tTest" color="7" fill="1" visible="no" active="no"/>
<layer number="38" name="bTest" color="7" fill="1" visible="no" active="no"/>
<layer number="39" name="tKeepout" color="4" fill="11" visible="no" active="no"/>
<layer number="40" name="bKeepout" color="1" fill="11" visible="no" active="no"/>
<layer number="41" name="tRestrict" color="4" fill="10" visible="no" active="no"/>
<layer number="42" name="bRestrict" color="1" fill="10" visible="no" active="no"/>
<layer number="43" name="vRestrict" color="2" fill="10" visible="no" active="no"/>
<layer number="44" name="Drills" color="7" fill="1" visible="no" active="no"/>
<layer number="45" name="Holes" color="7" fill="1" visible="no" active="no"/>
<layer number="46" name="Milling" color="3" fill="1" visible="no" active="no"/>
<layer number="47" name="Measures" color="7" fill="1" visible="no" active="no"/>
<layer number="48" name="Document" color="7" fill="1" visible="no" active="no"/>
<layer number="49" name="Reference" color="7" fill="1" visible="no" active="no"/>
<layer number="51" name="tDocu" color="7" fill="1" visible="no" active="no"/>
<layer number="52" name="bDocu" color="7" fill="1" visible="no" active="no"/>
<layer number="88" name="SimResults" color="9" fill="1" visible="yes" active="yes"/>
<layer number="89" name="SimProbes" color="9" fill="1" visible="yes" active="yes"/>
<layer number="90" name="Modules" color="5" fill="1" visible="yes" active="yes"/>
<layer number="91" name="Nets" color="2" fill="1" visible="yes" active="yes"/>
<layer number="92" name="Busses" color="1" fill="1" visible="yes" active="yes"/>
<layer number="93" name="Pins" color="2" fill="1" visible="no" active="yes"/>
<layer number="94" name="Symbols" color="4" fill="1" visible="yes" active="yes"/>
<layer number="95" name="Names" color="7" fill="1" visible="yes" active="yes"/>
<layer number="96" name="Values" color="7" fill="1" visible="yes" active="yes"/>
<layer number="97" name="Info" color="7" fill="1" visible="yes" active="yes"/>
<layer number="98" name="Guide" color="6" fill="1" visible="yes" active="yes"/>
</layers>
<schematic xreflabel="%F%N/%S.%C%R" xrefpart="/%S.%C%R">
<libraries>
<library name="MotionDetectorCamera">
<packages>
<package name="TSOP54-400" urn="urn:adsk.eagle:footprint:18732/1">
<description>&lt;b&gt;54-Pin Plastic TSOP&lt;/b&gt; (400 mil)&lt;p&gt;
Source: http://download.micron.com/pdf/datasheets/dram/sdram/256MSDRAM.pdf</description>
<wire x1="-11.0084" y1="1.4" x2="-11.0084" y2="3.4" width="0.2032" layer="21" curve="180"/>
<wire x1="11.0084" y1="-4.9784" x2="11.0084" y2="4.9784" width="0.2032" layer="21"/>
<wire x1="11.0084" y1="4.9784" x2="-11.0084" y2="4.9784" width="0.2032" layer="21"/>
<wire x1="-11.0084" y1="4.9784" x2="-11.0084" y2="3.4" width="0.2032" layer="21"/>
<wire x1="-11.0084" y1="3.4" x2="-11.0084" y2="1.4" width="0.2032" layer="21"/>
<wire x1="-11.0084" y1="1.4" x2="-11.0084" y2="-4.9784" width="0.2032" layer="21"/>
<wire x1="-11.0084" y1="-4.9784" x2="11.0084" y2="-4.9784" width="0.2032" layer="21"/>
<circle x="-10.4" y="-4.4" radius="0.4" width="0" layer="21"/>
<smd name="1" x="-10.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="2" x="-9.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="3" x="-8.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="4" x="-8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="5" x="-7.2" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="6" x="-6.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="7" x="-5.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="8" x="-4.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="9" x="-4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="10" x="-3.2" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="11" x="-2.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="12" x="-1.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="13" x="-0.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="14" x="0" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="15" x="0.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="16" x="1.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="17" x="2.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="18" x="3.2" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="19" x="4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="20" x="4.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="21" x="5.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="22" x="6.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="23" x="7.2" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="24" x="8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="25" x="8.8" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="26" x="9.6" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="27" x="10.4" y="-5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="28" x="10.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R270"/>
<smd name="29" x="9.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="30" x="8.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="31" x="8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="32" x="7.2" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="33" x="6.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="34" x="5.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="35" x="4.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="36" x="4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="37" x="3.2" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="38" x="2.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="39" x="1.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="40" x="0.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="41" x="0" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="42" x="-0.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="43" x="-1.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="44" x="-2.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="45" x="-3.2" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="46" x="-4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="47" x="-4.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="48" x="-5.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="49" x="-6.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="50" x="-7.2" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="51" x="-8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="52" x="-8.8" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="53" x="-9.6" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<smd name="54" x="-10.4" y="5.68" dx="0.9" dy="0.4" layer="1" rot="R90"/>
<text x="-11.6" y="-4.8" size="1.27" layer="25" rot="R90">&gt;NAME</text>
<text x="-6" y="-0.4" size="1.27" layer="27">&gt;VALUE</text>
<rectangle x1="-10.8" y1="-5.6675" x2="-10" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-10" y1="-5.6675" x2="-9.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-9.2" y1="-5.6675" x2="-8.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-8.4" y1="-5.6675" x2="-7.6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-7.6" y1="-5.6675" x2="-6.8" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-6.8" y1="-5.6675" x2="-6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-6" y1="-5.6675" x2="-5.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-5.2" y1="-5.6675" x2="-4.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-4.4" y1="-5.6675" x2="-3.6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-3.6" y1="-5.6675" x2="-2.8" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-2.8" y1="-5.6675" x2="-2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-2" y1="-5.6675" x2="-1.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-1.2" y1="-5.6675" x2="-0.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="-0.4" y1="-5.6675" x2="0.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="0.4" y1="-5.6675" x2="1.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="1.2" y1="-5.6675" x2="2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="2" y1="-5.6675" x2="2.8" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="2.8" y1="-5.6675" x2="3.6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="3.6" y1="-5.6675" x2="4.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="4.4" y1="-5.6675" x2="5.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="5.2" y1="-5.6675" x2="6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="6" y1="-5.6675" x2="6.8" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="6.8" y1="-5.6675" x2="7.6" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="7.6" y1="-5.6675" x2="8.4" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="8.4" y1="-5.6675" x2="9.2" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="9.2" y1="-5.6675" x2="10" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="10" y1="-5.6675" x2="10.8" y2="-5.2925" layer="51" rot="R90"/>
<rectangle x1="10" y1="5.2925" x2="10.8" y2="5.6675" layer="51" rot="R270"/>
<rectangle x1="9.2" y1="5.2925" x2="10" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="8.4" y1="5.2925" x2="9.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="7.6" y1="5.2925" x2="8.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="6.8" y1="5.2925" x2="7.6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="6" y1="5.2925" x2="6.8" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="5.2" y1="5.2925" x2="6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="4.4" y1="5.2925" x2="5.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="3.6" y1="5.2925" x2="4.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="2.8" y1="5.2925" x2="3.6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="2" y1="5.2925" x2="2.8" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="1.2" y1="5.2925" x2="2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="0.4" y1="5.2925" x2="1.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-0.4" y1="5.2925" x2="0.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-1.2" y1="5.2925" x2="-0.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-2" y1="5.2925" x2="-1.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-2.8" y1="5.2925" x2="-2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-3.6" y1="5.2925" x2="-2.8" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-4.4" y1="5.2925" x2="-3.6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-5.2" y1="5.2925" x2="-4.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-6" y1="5.2925" x2="-5.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-6.8" y1="5.2925" x2="-6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-7.6" y1="5.2925" x2="-6.8" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-8.4" y1="5.2925" x2="-7.6" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-9.2" y1="5.2925" x2="-8.4" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-10" y1="5.2925" x2="-9.2" y2="5.6675" layer="51" rot="R90"/>
<rectangle x1="-10.8" y1="5.2925" x2="-10" y2="5.6675" layer="51" rot="R90"/>
</package>
<package name="TQFP144">
<smd name="1" x="-10.6172" y="8.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="2" x="-10.6172" y="8.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="3" x="-10.6172" y="7.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="4" x="-10.6172" y="7.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="5" x="-10.6172" y="6.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="6" x="-10.6172" y="6.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="7" x="-10.6172" y="5.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="8" x="-10.6172" y="5.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="9" x="-10.6172" y="4.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="10" x="-10.6172" y="4.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="11" x="-10.6172" y="3.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="12" x="-10.6172" y="3.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="13" x="-10.6172" y="2.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="14" x="-10.6172" y="2.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="15" x="-10.6172" y="1.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="16" x="-10.6172" y="1.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="17" x="-10.6172" y="0.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="18" x="-10.6172" y="0.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="19" x="-10.6172" y="-0.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="20" x="-10.6172" y="-0.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="21" x="-10.6172" y="-1.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="22" x="-10.6172" y="-1.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="23" x="-10.6172" y="-2.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="24" x="-10.6172" y="-2.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="25" x="-10.6172" y="-3.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="26" x="-10.6172" y="-3.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="27" x="-10.6172" y="-4.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="28" x="-10.6172" y="-4.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="29" x="-10.6172" y="-5.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="30" x="-10.6172" y="-5.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="31" x="-10.6172" y="-6.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="32" x="-10.6172" y="-6.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="33" x="-10.6172" y="-7.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="34" x="-10.6172" y="-7.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="35" x="-10.6172" y="-8.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="36" x="-10.6172" y="-8.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="37" x="-8.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="38" x="-8.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="39" x="-7.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="40" x="-7.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="41" x="-6.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="42" x="-6.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="43" x="-5.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="44" x="-5.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="45" x="-4.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="46" x="-4.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="47" x="-3.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="48" x="-3.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="49" x="-2.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="50" x="-2.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="51" x="-1.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="52" x="-1.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="53" x="-0.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="54" x="-0.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="55" x="0.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="56" x="0.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="57" x="1.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="58" x="1.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="59" x="2.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="60" x="2.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="61" x="3.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="62" x="3.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="63" x="4.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="64" x="4.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="65" x="5.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="66" x="5.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="67" x="6.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="68" x="6.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="69" x="7.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="70" x="7.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="71" x="8.25" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="72" x="8.75" y="-10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="73" x="10.6172" y="-8.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="74" x="10.6172" y="-8.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="75" x="10.6172" y="-7.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="76" x="10.6172" y="-7.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="77" x="10.6172" y="-6.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="78" x="10.6172" y="-6.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="79" x="10.6172" y="-5.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="80" x="10.6172" y="-5.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="81" x="10.6172" y="-4.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="82" x="10.6172" y="-4.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="83" x="10.6172" y="-3.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="84" x="10.6172" y="-3.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="85" x="10.6172" y="-2.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="86" x="10.6172" y="-2.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="87" x="10.6172" y="-1.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="88" x="10.6172" y="-1.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="89" x="10.6172" y="-0.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="90" x="10.6172" y="-0.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="91" x="10.6172" y="0.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="92" x="10.6172" y="0.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="93" x="10.6172" y="1.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="94" x="10.6172" y="1.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="95" x="10.6172" y="2.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="96" x="10.6172" y="2.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="97" x="10.6172" y="3.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="98" x="10.6172" y="3.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="99" x="10.6172" y="4.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="100" x="10.6172" y="4.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="101" x="10.6172" y="5.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="102" x="10.6172" y="5.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="103" x="10.6172" y="6.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="104" x="10.6172" y="6.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="105" x="10.6172" y="7.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="106" x="10.6172" y="7.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="107" x="10.6172" y="8.25" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="108" x="10.6172" y="8.75" dx="0.2794" dy="1.4732" layer="1" rot="R270"/>
<smd name="109" x="8.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="110" x="8.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="111" x="7.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="112" x="7.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="113" x="6.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="114" x="6.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="115" x="5.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="116" x="5.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="117" x="4.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="118" x="4.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="119" x="3.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="120" x="3.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="121" x="2.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="122" x="2.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="123" x="1.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="124" x="1.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="125" x="0.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="126" x="0.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="127" x="-0.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="128" x="-0.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="129" x="-1.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="130" x="-1.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="131" x="-2.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="132" x="-2.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="133" x="-3.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="134" x="-3.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="135" x="-4.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="136" x="-4.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="137" x="-5.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="138" x="-5.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="139" x="-6.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="140" x="-6.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="141" x="-7.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="142" x="-7.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="143" x="-8.25" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<smd name="144" x="-8.75" y="10.6172" dx="0.2794" dy="1.4732" layer="1" rot="R180"/>
<wire x1="-10.1092" y1="-10.1092" x2="-9.2202" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="-10.1092" x2="10.1092" y2="-9.2202" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="10.1092" x2="9.2202" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="10.1092" x2="-10.1092" y2="9.2202" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="-9.2202" x2="-10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="9.2202" y1="-10.1092" x2="10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="9.2202" x2="10.1092" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-9.2202" y1="10.1092" x2="-10.1092" y2="10.1092" width="0.1524" layer="21"/>
<polygon width="0.0254" layer="21">
<vertex x="-11.8618" y="4.4405"/>
<vertex x="-11.8618" y="4.0595"/>
<vertex x="-11.6078" y="4.0595"/>
<vertex x="-11.6078" y="4.4405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-11.8618" y="-0.5595"/>
<vertex x="-11.8618" y="-0.9405"/>
<vertex x="-11.6078" y="-0.9405"/>
<vertex x="-11.6078" y="-0.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-11.8618" y="-5.5595"/>
<vertex x="-11.8618" y="-5.9405"/>
<vertex x="-11.6078" y="-5.9405"/>
<vertex x="-11.6078" y="-5.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-7.4405" y="-11.6078"/>
<vertex x="-7.4405" y="-11.8618"/>
<vertex x="-7.0595" y="-11.8618"/>
<vertex x="-7.0595" y="-11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-2.4405" y="-11.6078"/>
<vertex x="-2.4405" y="-11.8618"/>
<vertex x="-2.0595" y="-11.8618"/>
<vertex x="-2.0595" y="-11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="2.5595" y="-11.6078"/>
<vertex x="2.5595" y="-11.8618"/>
<vertex x="2.9405" y="-11.8618"/>
<vertex x="2.9405" y="-11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="7.5595" y="-11.6078"/>
<vertex x="7.5595" y="-11.8618"/>
<vertex x="7.9405" y="-11.8618"/>
<vertex x="7.9405" y="-11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.8618" y="-5.0595"/>
<vertex x="11.8618" y="-5.4405"/>
<vertex x="11.6078" y="-5.4405"/>
<vertex x="11.6078" y="-5.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.8618" y="-0.0595"/>
<vertex x="11.8618" y="-0.4405"/>
<vertex x="11.6078" y="-0.4405"/>
<vertex x="11.6078" y="-0.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.8618" y="4.9405"/>
<vertex x="11.8618" y="4.5595"/>
<vertex x="11.6078" y="4.5595"/>
<vertex x="11.6078" y="4.9405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="8.0595" y="11.6078"/>
<vertex x="8.0595" y="11.8618"/>
<vertex x="8.4405" y="11.8618"/>
<vertex x="8.4405" y="11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="3.0595" y="11.6078"/>
<vertex x="3.0595" y="11.8618"/>
<vertex x="3.4405" y="11.8618"/>
<vertex x="3.4405" y="11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-1.9405" y="11.6078"/>
<vertex x="-1.9405" y="11.8618"/>
<vertex x="-1.5595" y="11.8618"/>
<vertex x="-1.5595" y="11.6078"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-6.9405" y="11.6078"/>
<vertex x="-6.9405" y="11.8618"/>
<vertex x="-6.5595" y="11.8618"/>
<vertex x="-6.5595" y="11.6078"/>
</polygon>
<text x="-12.573" y="8.7376" size="1.27" layer="21" ratio="6" rot="SR0">*</text>
<wire x1="-10.2616" y1="-10.2616" x2="-10.2616" y2="-9.144" width="0.1524" layer="51"/>
<wire x1="-10.2616" y1="-9.144" x2="-11.6078" y2="-9.144" width="0.1524" layer="51"/>
<wire x1="-11.6078" y1="-9.144" x2="-11.6078" y2="9.144" width="0.1524" layer="51"/>
<wire x1="-11.6078" y1="9.144" x2="-10.2616" y2="9.144" width="0.1524" layer="51"/>
<wire x1="-10.2616" y1="9.144" x2="-10.2616" y2="10.2616" width="0.1524" layer="51"/>
<wire x1="10.2616" y1="-10.2616" x2="10.2616" y2="-9.144" width="0.1524" layer="51"/>
<wire x1="10.2616" y1="-9.144" x2="11.6078" y2="-9.144" width="0.1524" layer="51"/>
<wire x1="11.6078" y1="-9.144" x2="11.6078" y2="9.144" width="0.1524" layer="51"/>
<wire x1="11.6078" y1="9.144" x2="10.2616" y2="9.144" width="0.1524" layer="51"/>
<wire x1="10.2616" y1="9.144" x2="10.2616" y2="10.2616" width="0.1524" layer="51"/>
<wire x1="-10.2616" y1="10.2616" x2="-9.144" y2="10.2616" width="0.1524" layer="51"/>
<wire x1="-9.144" y1="10.2616" x2="-9.144" y2="11.6078" width="0.1524" layer="51"/>
<wire x1="-9.144" y1="11.6078" x2="9.144" y2="11.6078" width="0.1524" layer="51"/>
<wire x1="9.144" y1="11.6078" x2="9.144" y2="10.2616" width="0.1524" layer="51"/>
<wire x1="9.144" y1="10.2616" x2="10.2616" y2="10.2616" width="0.1524" layer="51"/>
<wire x1="-10.2616" y1="-10.2616" x2="-9.144" y2="-10.2616" width="0.1524" layer="51"/>
<wire x1="-9.144" y1="-10.2616" x2="-9.144" y2="-11.6078" width="0.1524" layer="51"/>
<wire x1="-9.144" y1="-11.6078" x2="9.144" y2="-11.6078" width="0.1524" layer="51"/>
<wire x1="9.144" y1="-11.6078" x2="9.144" y2="-10.2616" width="0.1524" layer="51"/>
<wire x1="9.144" y1="-10.2616" x2="10.2616" y2="-10.2616" width="0.1524" layer="51"/>
<polygon width="0.1524" layer="51">
<vertex x="-10.2489" y="-10.2489"/>
<vertex x="-10.2489" y="-9.1437"/>
<vertex x="-11.6078" y="-9.1437"/>
<vertex x="-11.6078" y="9.1437"/>
<vertex x="-10.2489" y="9.1437"/>
<vertex x="-10.2489" y="10.2489"/>
<vertex x="-9.1437" y="10.2489"/>
<vertex x="-9.1437" y="11.6078"/>
<vertex x="9.1437" y="11.6078"/>
<vertex x="9.1437" y="10.2489"/>
<vertex x="10.2489" y="10.2489"/>
<vertex x="10.2489" y="9.1437"/>
<vertex x="11.6078" y="9.1437"/>
<vertex x="11.6078" y="-9.1437"/>
<vertex x="10.2489" y="-9.1437"/>
<vertex x="10.2489" y="-10.2489"/>
<vertex x="9.1437" y="-10.2489"/>
<vertex x="9.1437" y="-11.6078"/>
<vertex x="-9.1437" y="-11.6078"/>
<vertex x="-9.1437" y="-10.2489"/>
</polygon>
<wire x1="10.6172" y1="8.7376" x2="10.9982" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="13.5382" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.7376" x2="13.9192" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.6172" y1="8.255" x2="13.5382" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.255" x2="13.9192" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.7376" x2="13.5382" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.255" x2="13.5382" y2="6.985" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.7376" x2="13.4112" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.7376" x2="13.6652" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.4112" y1="8.9916" x2="13.6652" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.255" x2="13.4112" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.5382" y1="8.255" x2="13.6652" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.4112" y1="8.001" x2="13.6652" y2="8.001" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="8.7376" x2="10.2362" y2="13.5382" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.5382" x2="10.2362" y2="13.9192" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="10.9982" y2="13.5382" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.5382" x2="8.9662" y2="13.5382" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.5382" x2="12.2682" y2="13.5382" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.5382" x2="9.9822" y2="13.6652" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.5382" x2="9.9822" y2="13.4112" width="0.1524" layer="20"/>
<wire x1="9.9822" y1="13.6652" x2="9.9822" y2="13.4112" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.5382" x2="11.2522" y2="13.6652" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.5382" x2="11.2522" y2="13.4112" width="0.1524" layer="20"/>
<wire x1="11.2522" y1="13.6652" x2="11.2522" y2="13.4112" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="8.7376" x2="-10.9982" y2="15.4432" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.4432" x2="-10.9982" y2="15.8242" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.5382" x2="10.9982" y2="15.4432" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.4432" x2="10.9982" y2="15.8242" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.4432" x2="10.9982" y2="15.4432" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.4432" x2="-10.7442" y2="15.5702" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.4432" x2="-10.7442" y2="15.3162" width="0.1524" layer="20"/>
<wire x1="-10.7442" y1="15.5702" x2="-10.7442" y2="15.3162" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.4432" x2="10.7442" y2="15.5702" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.4432" x2="10.7442" y2="15.3162" width="0.1524" layer="20"/>
<wire x1="10.7442" y1="15.5702" x2="10.7442" y2="15.3162" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-8.7376" x2="-10.0076" y2="-13.5382" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.5382" x2="-10.0076" y2="-13.9192" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-8.7376" x2="10.0076" y2="-13.5382" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.5382" x2="10.0076" y2="-13.9192" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.5382" x2="10.0076" y2="-13.5382" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.5382" x2="-9.7536" y2="-13.4112" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.5382" x2="-9.7536" y2="-13.6652" width="0.1524" layer="20"/>
<wire x1="-9.7536" y1="-13.4112" x2="-9.7536" y2="-13.6652" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.5382" x2="9.7536" y2="-13.4112" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.5382" x2="9.7536" y2="-13.6652" width="0.1524" layer="20"/>
<wire x1="9.7536" y1="-13.4112" x2="9.7536" y2="-13.6652" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="10.0076" x2="-13.5382" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="10.0076" x2="-13.9192" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="-10.0076" x2="-13.5382" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="-10.0076" x2="-13.9192" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="10.0076" x2="-13.5382" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="10.0076" x2="-13.6652" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="10.0076" x2="-13.4112" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.6652" y1="9.7536" x2="-13.4112" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="-10.0076" x2="-13.6652" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.5382" y1="-10.0076" x2="-13.4112" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.6652" y1="-9.7536" x2="-13.4112" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="10.9982" x2="15.4432" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="10.9982" x2="15.8242" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="-10.9982" x2="15.4432" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="-10.9982" x2="15.8242" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="10.9982" x2="15.4432" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="10.9982" x2="15.3162" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="10.9982" x2="15.5702" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.3162" y1="10.7442" x2="15.5702" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="-10.9982" x2="15.3162" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.4432" y1="-10.9982" x2="15.5702" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.3162" y1="-10.7442" x2="15.5702" y2="-10.7442" width="0.1524" layer="20"/>
<text x="-16.7386" y="-17.3482" size="1.27" layer="20" ratio="6" rot="SR0">Default Horiz Padstyle: r28_147</text>
<text x="-16.1798" y="-18.8722" size="1.27" layer="20" ratio="6" rot="SR0">Default Vert Padstyle: r28_147</text>
<text x="-14.8082" y="-23.4442" size="1.27" layer="20" ratio="6" rot="SR0">Alt 1 Padstyle: b152_229h76</text>
<text x="-14.8082" y="-24.9682" size="1.27" layer="20" ratio="6" rot="SR0">Alt 2 Padstyle: b229_152h76</text>
<text x="14.0462" y="8.1788" size="0.635" layer="20" ratio="4" rot="SR0">0.02in/0.5mm</text>
<text x="6.858" y="14.0462" size="0.635" layer="20" ratio="4" rot="SR0">0.03in/0.762mm</text>
<text x="-4.318" y="15.9512" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<text x="-4.0386" y="-14.6812" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="-22.1234" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="15.9512" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<wire x1="8.6106" y1="10.0076" x2="8.89" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.0076" x2="8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.9982" x2="8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="10.9982" x2="8.6106" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.0076" x2="8.382" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.0076" x2="8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.9982" x2="8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.9982" x2="8.1026" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="9.9822" x2="7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="9.9822" x2="7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="10.9982" x2="7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="10.9982" x2="7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.112" y1="9.9822" x2="7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="9.9822" x2="7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="10.9982" x2="7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="10.9982" x2="7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.604" y1="9.9822" x2="6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="9.9822" x2="6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="10.9982" x2="6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="10.9982" x2="6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="9.9822" x2="6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="9.9822" x2="6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="10.9982" x2="6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="10.9982" x2="6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="9.9822" x2="5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="9.9822" x2="5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="10.9982" x2="5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="10.9982" x2="5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="9.9822" x2="5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="9.9822" x2="5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="10.9982" x2="5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="10.9982" x2="5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="9.9822" x2="4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="9.9822" x2="4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="10.9982" x2="4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="10.9982" x2="4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="9.9822" x2="4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="9.9822" x2="4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="10.9982" x2="4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="10.9982" x2="4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="9.9822" x2="3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="9.9822" x2="3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="10.9982" x2="3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="10.9982" x2="3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="9.9822" x2="3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="9.9822" x2="3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="10.9982" x2="3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="10.9982" x2="3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="9.9822" x2="2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="9.9822" x2="2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="10.9982" x2="2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="10.9982" x2="2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="9.9822" x2="2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="9.9822" x2="2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="10.9982" x2="2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="10.9982" x2="2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="9.9822" x2="1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="9.9822" x2="1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="10.9982" x2="1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="10.9982" x2="1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="9.9822" x2="1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.397" y1="9.9822" x2="1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="10.9982" x2="1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="10.9982" x2="1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="9.9822" x2="0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.889" y1="9.9822" x2="0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="10.9982" x2="0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="10.9982" x2="0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="9.9822" x2="0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.381" y1="9.9822" x2="0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="10.9982" x2="0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="10.9982" x2="0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="9.9822" x2="-0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="9.9822" x2="-0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="10.9982" x2="-0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="10.9982" x2="-0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="9.9822" x2="-0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="9.9822" x2="-0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="10.9982" x2="-0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="10.9982" x2="-0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="9.9822" x2="-1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="9.9822" x2="-1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="10.9982" x2="-1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="10.9982" x2="-1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="9.9822" x2="-1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="9.9822" x2="-1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="10.9982" x2="-1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="10.9982" x2="-1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="9.9822" x2="-2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="9.9822" x2="-2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="10.9982" x2="-2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="10.9982" x2="-2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="9.9822" x2="-2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="9.9822" x2="-2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="10.9982" x2="-2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="10.9982" x2="-2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="9.9822" x2="-3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="9.9822" x2="-3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="10.9982" x2="-3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="10.9982" x2="-3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="9.9822" x2="-3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="9.9822" x2="-3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="10.9982" x2="-3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="10.9982" x2="-3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="9.9822" x2="-4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="9.9822" x2="-4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="10.9982" x2="-4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="10.9982" x2="-4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="9.9822" x2="-4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="9.9822" x2="-4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="10.9982" x2="-4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="10.9982" x2="-4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="9.9822" x2="-5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="9.9822" x2="-5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="10.9982" x2="-5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="10.9982" x2="-5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="9.9822" x2="-5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="9.9822" x2="-5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="10.9982" x2="-5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="10.9982" x2="-5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="9.9822" x2="-6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="9.9822" x2="-6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="10.9982" x2="-6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="10.9982" x2="-6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="9.9822" x2="-6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="9.9822" x2="-6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="10.9982" x2="-6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="10.9982" x2="-6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="9.9822" x2="-7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="9.9822" x2="-7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="10.9982" x2="-7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="10.9982" x2="-7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="9.9822" x2="-7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="9.9822" x2="-7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="10.9982" x2="-7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="10.9982" x2="-7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="9.9822" x2="-8.1026" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="9.9822" x2="-8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="10.9982" x2="-8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="10.9982" x2="-8.382" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="9.9822" x2="-8.6106" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="9.9822" x2="-8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="10.9982" x2="-8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="10.9982" x2="-8.89" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.6106" x2="-10.0076" y2="8.7376" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-10.0076" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.89" x2="-10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.89" x2="-10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.6106" x2="-10.0076" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.1026" x2="-10.0076" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.382" x2="-10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.382" x2="-10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.1026" x2="-10.0076" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.62" x2="-10.0076" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.8994" x2="-10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.8994" x2="-10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.62" x2="-10.0076" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.112" x2="-9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.3914" x2="-10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.3914" x2="-10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.112" x2="-9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.604" x2="-9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.8834" x2="-10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.8834" x2="-10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.604" x2="-9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.1214" x2="-9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.4008" x2="-10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.4008" x2="-10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.1214" x2="-9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.6134" x2="-9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.8928" x2="-10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.8928" x2="-10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.6134" x2="-9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.1054" x2="-9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.3848" x2="-10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.3848" x2="-10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.1054" x2="-9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.6228" x2="-9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.9022" x2="-10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.9022" x2="-10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.6228" x2="-9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.1148" x2="-9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.3942" x2="-10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.3942" x2="-10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.1148" x2="-9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.6068" x2="-9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.8862" x2="-10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.8862" x2="-10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.6068" x2="-9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.0988" x2="-9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.3782" x2="-10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.3782" x2="-10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.0988" x2="-9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.6162" x2="-9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.8956" x2="-10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.8956" x2="-10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.6162" x2="-9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.1082" x2="-9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.3876" x2="-10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.3876" x2="-10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.1082" x2="-9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.6002" x2="-9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.8796" x2="-10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.8796" x2="-10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.6002" x2="-9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.1176" x2="-9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.397" x2="-10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.397" x2="-10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.1176" x2="-9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.6096" x2="-9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.889" x2="-10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.889" x2="-10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.6096" x2="-9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.1016" x2="-9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.381" x2="-10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.381" x2="-10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.1016" x2="-9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.381" x2="-9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.1016" x2="-10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.1016" x2="-10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.381" x2="-9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.889" x2="-9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.6096" x2="-10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.6096" x2="-10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.889" x2="-9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.397" x2="-9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.1176" x2="-10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.1176" x2="-10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.397" x2="-9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.8796" x2="-9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.6002" x2="-10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.6002" x2="-10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.8796" x2="-9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.3876" x2="-9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.1082" x2="-10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.1082" x2="-10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.3876" x2="-9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.8956" x2="-9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.6162" x2="-10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.6162" x2="-10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.8956" x2="-9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.3782" x2="-9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.0988" x2="-10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.0988" x2="-10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.3782" x2="-9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.8862" x2="-9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.6068" x2="-10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.6068" x2="-10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.8862" x2="-9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.3942" x2="-9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.1148" x2="-10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.1148" x2="-10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.3942" x2="-9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.9022" x2="-9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.6228" x2="-10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.6228" x2="-10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.9022" x2="-9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.3848" x2="-9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.1054" x2="-10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.1054" x2="-10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.3848" x2="-9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.8928" x2="-9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.6134" x2="-10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.6134" x2="-10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.8928" x2="-9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.4008" x2="-9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.1214" x2="-10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.1214" x2="-10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.4008" x2="-9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.8834" x2="-9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.604" x2="-10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.604" x2="-10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.8834" x2="-9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.3914" x2="-9.9822" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.112" x2="-10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.112" x2="-10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.3914" x2="-9.9822" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.8994" x2="-9.9822" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.62" x2="-10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.62" x2="-10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.8994" x2="-9.9822" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.382" x2="-9.9822" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.1026" x2="-10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.1026" x2="-10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.382" x2="-9.9822" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.89" x2="-9.9822" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.6106" x2="-10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.6106" x2="-10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.89" x2="-9.9822" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.0076" x2="-8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.0076" x2="-8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.9982" x2="-8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.9982" x2="-8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.0076" x2="-8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.0076" x2="-8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.9982" x2="-8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.9982" x2="-8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.0076" x2="-7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.0076" x2="-7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.9982" x2="-7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.9982" x2="-7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.0076" x2="-7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.0076" x2="-7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.9982" x2="-7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.9982" x2="-7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.0076" x2="-6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.0076" x2="-6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.9982" x2="-6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.9982" x2="-6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.0076" x2="-6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.0076" x2="-6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.9982" x2="-6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.9982" x2="-6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.0076" x2="-5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.0076" x2="-5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.9982" x2="-5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.9982" x2="-5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.0076" x2="-5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.0076" x2="-5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.9982" x2="-5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.9982" x2="-5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.0076" x2="-4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.0076" x2="-4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.9982" x2="-4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.9982" x2="-4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.0076" x2="-4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.0076" x2="-4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.9982" x2="-4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.9982" x2="-4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.0076" x2="-3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.0076" x2="-3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.9982" x2="-3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.9982" x2="-3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.0076" x2="-3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.0076" x2="-3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.9982" x2="-3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.9982" x2="-3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.0076" x2="-2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.0076" x2="-2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.9982" x2="-2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.9982" x2="-2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.0076" x2="-2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.0076" x2="-2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.9982" x2="-2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.9982" x2="-2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.0076" x2="-1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.0076" x2="-1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.9982" x2="-1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.9982" x2="-1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.0076" x2="-1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.0076" x2="-1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.9982" x2="-1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.9982" x2="-1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.0076" x2="-0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.0076" x2="-0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.9982" x2="-0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.9982" x2="-0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.0076" x2="-0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.0076" x2="-0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.9982" x2="-0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.9982" x2="-0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.0076" x2="0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.0076" x2="0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.9982" x2="0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.9982" x2="0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.0076" x2="0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.0076" x2="0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.9982" x2="0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.9982" x2="0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.0076" x2="1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.0076" x2="1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.9982" x2="1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.9982" x2="1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.0076" x2="1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.0076" x2="1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.9982" x2="1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.9982" x2="1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.0076" x2="2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.0076" x2="2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.9982" x2="2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.9982" x2="2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.0076" x2="2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.0076" x2="2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.9982" x2="2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.9982" x2="2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.0076" x2="3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.0076" x2="3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.9982" x2="3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.9982" x2="3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.0076" x2="3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.0076" x2="3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.9982" x2="3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.9982" x2="3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.0076" x2="4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.0076" x2="4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.9982" x2="4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.9982" x2="4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.0076" x2="4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.0076" x2="4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.9982" x2="4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.9982" x2="4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.0076" x2="5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.0076" x2="5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.9982" x2="5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.9982" x2="5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.0076" x2="5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.0076" x2="5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.9982" x2="5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.9982" x2="5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.0076" x2="6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.0076" x2="6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.9982" x2="6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.9982" x2="6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.0076" x2="6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.0076" x2="6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.9982" x2="6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.9982" x2="6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.0076" x2="7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.0076" x2="7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.9982" x2="7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.9982" x2="7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.0076" x2="7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.0076" x2="7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.9982" x2="7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.9982" x2="7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.0076" x2="8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.0076" x2="8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.9982" x2="8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.9982" x2="8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.0076" x2="8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.0076" x2="8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.9982" x2="8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.9982" x2="8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.6106" x2="10.0076" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.89" x2="10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.89" x2="10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.6106" x2="10.0076" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.1026" x2="10.0076" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.382" x2="10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.382" x2="10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.1026" x2="10.0076" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.62" x2="10.0076" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.8994" x2="10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.8994" x2="10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.62" x2="10.0076" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.112" x2="10.0076" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.3914" x2="10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.3914" x2="10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.112" x2="10.0076" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.604" x2="9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.8834" x2="10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.8834" x2="10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.604" x2="9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.1214" x2="9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.4008" x2="10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.4008" x2="10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.1214" x2="9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.6134" x2="9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.8928" x2="10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.8928" x2="10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.6134" x2="9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.1054" x2="9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.3848" x2="10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.3848" x2="10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.1054" x2="9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.6228" x2="9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.9022" x2="10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.9022" x2="10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.6228" x2="9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.1148" x2="9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.3942" x2="10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.3942" x2="10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.1148" x2="9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.6068" x2="9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.8862" x2="10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.8862" x2="10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.6068" x2="9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.0988" x2="9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.3782" x2="10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.3782" x2="10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.0988" x2="9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.6162" x2="9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.8956" x2="10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.8956" x2="10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.6162" x2="9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.1082" x2="9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.3876" x2="10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.3876" x2="10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.1082" x2="9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.6002" x2="9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.8796" x2="10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.8796" x2="10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.6002" x2="9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.1176" x2="9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.397" x2="10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.397" x2="10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.1176" x2="9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.6096" x2="9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.889" x2="10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.889" x2="10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.6096" x2="9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.1016" x2="9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.381" x2="10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.381" x2="10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.1016" x2="9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.381" x2="9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.1016" x2="10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.1016" x2="10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.381" x2="9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.889" x2="9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.6096" x2="10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.6096" x2="10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.889" x2="9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.397" x2="9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.1176" x2="10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.1176" x2="10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.397" x2="9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.8796" x2="9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.6002" x2="10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.6002" x2="10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.8796" x2="9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.3876" x2="9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.1082" x2="10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.1082" x2="10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.3876" x2="9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.8956" x2="9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.6162" x2="10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.6162" x2="10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.8956" x2="9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.3782" x2="9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.0988" x2="10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.0988" x2="10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.3782" x2="9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.8862" x2="9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.6068" x2="10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.6068" x2="10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.8862" x2="9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.3942" x2="9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.1148" x2="10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.1148" x2="10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.3942" x2="9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.9022" x2="9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.6228" x2="10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.6228" x2="10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.9022" x2="9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.3848" x2="9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.1054" x2="10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.1054" x2="10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.3848" x2="9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.8928" x2="9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.6134" x2="10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.6134" x2="10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.8928" x2="9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.4008" x2="9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.1214" x2="10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.1214" x2="10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.4008" x2="9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.8834" x2="9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.604" x2="10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.604" x2="10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.8834" x2="9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.3914" x2="9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.112" x2="10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.112" x2="10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.3914" x2="9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.8994" x2="9.9822" y2="7.62" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.62" x2="10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.62" x2="10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.8994" x2="9.9822" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.382" x2="9.9822" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.1026" x2="10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.1026" x2="10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.382" x2="9.9822" y2="8.382" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.89" x2="9.9822" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.6106" x2="10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.6106" x2="10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.89" x2="9.9822" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-8.7376" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="-10.0076" x2="10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-10.0076" x2="10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="10.0076" x2="-10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="10.0076" x2="-10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<text x="-10.1854" y="8.3566" size="1.27" layer="51" ratio="6" rot="SR0">*</text>
<wire x1="-0.254" y1="0" x2="0.254" y2="0" width="0.1524" layer="23"/>
<wire x1="0" y1="-0.254" x2="0" y2="0.254" width="0.1524" layer="23"/>
<text x="-3.2766" y="-0.635" size="1.27" layer="25" ratio="6" rot="SR0">&gt;Name</text>
</package>
<package name="TQFP144-M">
<smd name="1" x="-10.668" y="8.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="2" x="-10.668" y="8.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="3" x="-10.668" y="7.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="4" x="-10.668" y="7.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="5" x="-10.668" y="6.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="6" x="-10.668" y="6.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="7" x="-10.668" y="5.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="8" x="-10.668" y="5.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="9" x="-10.668" y="4.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="10" x="-10.668" y="4.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="11" x="-10.668" y="3.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="12" x="-10.668" y="3.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="13" x="-10.668" y="2.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="14" x="-10.668" y="2.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="15" x="-10.668" y="1.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="16" x="-10.668" y="1.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="17" x="-10.668" y="0.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="18" x="-10.668" y="0.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="19" x="-10.668" y="-0.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="20" x="-10.668" y="-0.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="21" x="-10.668" y="-1.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="22" x="-10.668" y="-1.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="23" x="-10.668" y="-2.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="24" x="-10.668" y="-2.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="25" x="-10.668" y="-3.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="26" x="-10.668" y="-3.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="27" x="-10.668" y="-4.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="28" x="-10.668" y="-4.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="29" x="-10.668" y="-5.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="30" x="-10.668" y="-5.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="31" x="-10.668" y="-6.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="32" x="-10.668" y="-6.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="33" x="-10.668" y="-7.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="34" x="-10.668" y="-7.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="35" x="-10.668" y="-8.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="36" x="-10.668" y="-8.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="37" x="-8.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="38" x="-8.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="39" x="-7.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="40" x="-7.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="41" x="-6.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="42" x="-6.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="43" x="-5.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="44" x="-5.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="45" x="-4.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="46" x="-4.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="47" x="-3.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="48" x="-3.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="49" x="-2.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="50" x="-2.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="51" x="-1.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="52" x="-1.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="53" x="-0.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="54" x="-0.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="55" x="0.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="56" x="0.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="57" x="1.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="58" x="1.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="59" x="2.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="60" x="2.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="61" x="3.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="62" x="3.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="63" x="4.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="64" x="4.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="65" x="5.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="66" x="5.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="67" x="6.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="68" x="6.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="69" x="7.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="70" x="7.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="71" x="8.25" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="72" x="8.75" y="-10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="73" x="10.668" y="-8.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="74" x="10.668" y="-8.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="75" x="10.668" y="-7.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="76" x="10.668" y="-7.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="77" x="10.668" y="-6.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="78" x="10.668" y="-6.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="79" x="10.668" y="-5.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="80" x="10.668" y="-5.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="81" x="10.668" y="-4.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="82" x="10.668" y="-4.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="83" x="10.668" y="-3.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="84" x="10.668" y="-3.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="85" x="10.668" y="-2.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="86" x="10.668" y="-2.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="87" x="10.668" y="-1.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="88" x="10.668" y="-1.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="89" x="10.668" y="-0.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="90" x="10.668" y="-0.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="91" x="10.668" y="0.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="92" x="10.668" y="0.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="93" x="10.668" y="1.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="94" x="10.668" y="1.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="95" x="10.668" y="2.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="96" x="10.668" y="2.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="97" x="10.668" y="3.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="98" x="10.668" y="3.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="99" x="10.668" y="4.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="100" x="10.668" y="4.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="101" x="10.668" y="5.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="102" x="10.668" y="5.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="103" x="10.668" y="6.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="104" x="10.668" y="6.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="105" x="10.668" y="7.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="106" x="10.668" y="7.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="107" x="10.668" y="8.25" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="108" x="10.668" y="8.75" dx="0.2794" dy="1.778" layer="1" rot="R270"/>
<smd name="109" x="8.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="110" x="8.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="111" x="7.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="112" x="7.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="113" x="6.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="114" x="6.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="115" x="5.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="116" x="5.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="117" x="4.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="118" x="4.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="119" x="3.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="120" x="3.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="121" x="2.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="122" x="2.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="123" x="1.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="124" x="1.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="125" x="0.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="126" x="0.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="127" x="-0.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="128" x="-0.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="129" x="-1.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="130" x="-1.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="131" x="-2.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="132" x="-2.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="133" x="-3.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="134" x="-3.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="135" x="-4.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="136" x="-4.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="137" x="-5.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="138" x="-5.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="139" x="-6.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="140" x="-6.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="141" x="-7.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="142" x="-7.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="143" x="-8.25" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<smd name="144" x="-8.75" y="10.668" dx="0.2794" dy="1.778" layer="1" rot="R180"/>
<wire x1="-10.1092" y1="-10.1092" x2="-9.2202" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="-10.1092" x2="10.1092" y2="-9.2202" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="10.1092" x2="9.2202" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="10.1092" x2="-10.1092" y2="9.2202" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="-9.2202" x2="-10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="9.2202" y1="-10.1092" x2="10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="9.2202" x2="10.1092" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-9.2202" y1="10.1092" x2="-10.1092" y2="10.1092" width="0.1524" layer="21"/>
<polygon width="0.0254" layer="21">
<vertex x="-12.065" y="4.4405"/>
<vertex x="-12.065" y="4.0595"/>
<vertex x="-11.811" y="4.0595"/>
<vertex x="-11.811" y="4.4405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-12.065" y="-0.5595"/>
<vertex x="-12.065" y="-0.9405"/>
<vertex x="-11.811" y="-0.9405"/>
<vertex x="-11.811" y="-0.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-12.065" y="-5.5595"/>
<vertex x="-12.065" y="-5.9405"/>
<vertex x="-11.811" y="-5.9405"/>
<vertex x="-11.811" y="-5.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-7.4405" y="-11.811"/>
<vertex x="-7.4405" y="-12.065"/>
<vertex x="-7.0595" y="-12.065"/>
<vertex x="-7.0595" y="-11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-2.4405" y="-11.811"/>
<vertex x="-2.4405" y="-12.065"/>
<vertex x="-2.0595" y="-12.065"/>
<vertex x="-2.0595" y="-11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="2.5595" y="-11.811"/>
<vertex x="2.5595" y="-12.065"/>
<vertex x="2.9405" y="-12.065"/>
<vertex x="2.9405" y="-11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="7.5595" y="-11.811"/>
<vertex x="7.5595" y="-12.065"/>
<vertex x="7.9405" y="-12.065"/>
<vertex x="7.9405" y="-11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="12.065" y="-5.0595"/>
<vertex x="12.065" y="-5.4405"/>
<vertex x="11.811" y="-5.4405"/>
<vertex x="11.811" y="-5.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="12.065" y="-0.0595"/>
<vertex x="12.065" y="-0.4405"/>
<vertex x="11.811" y="-0.4405"/>
<vertex x="11.811" y="-0.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="12.065" y="4.9405"/>
<vertex x="12.065" y="4.5595"/>
<vertex x="11.811" y="4.5595"/>
<vertex x="11.811" y="4.9405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="8.0595" y="11.811"/>
<vertex x="8.0595" y="12.065"/>
<vertex x="8.4405" y="12.065"/>
<vertex x="8.4405" y="11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="3.0595" y="11.811"/>
<vertex x="3.0595" y="12.065"/>
<vertex x="3.4405" y="12.065"/>
<vertex x="3.4405" y="11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-1.9405" y="11.811"/>
<vertex x="-1.9405" y="12.065"/>
<vertex x="-1.5595" y="12.065"/>
<vertex x="-1.5595" y="11.811"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-6.9405" y="11.811"/>
<vertex x="-6.9405" y="12.065"/>
<vertex x="-6.5595" y="12.065"/>
<vertex x="-6.5595" y="11.811"/>
</polygon>
<text x="-12.7762" y="8.7376" size="1.27" layer="21" ratio="6" rot="SR0">*</text>
<wire x1="-10.5156" y1="-10.5156" x2="-10.5156" y2="-9.398" width="0.1524" layer="51"/>
<wire x1="-10.5156" y1="-9.398" x2="-12.065" y2="-9.398" width="0.1524" layer="51"/>
<wire x1="-12.065" y1="-9.398" x2="-12.065" y2="9.398" width="0.1524" layer="51"/>
<wire x1="-12.065" y1="9.398" x2="-10.5156" y2="9.398" width="0.1524" layer="51"/>
<wire x1="-10.5156" y1="9.398" x2="-10.5156" y2="10.5156" width="0.1524" layer="51"/>
<wire x1="10.5156" y1="-10.5156" x2="10.5156" y2="-9.398" width="0.1524" layer="51"/>
<wire x1="10.5156" y1="-9.398" x2="12.065" y2="-9.398" width="0.1524" layer="51"/>
<wire x1="12.065" y1="-9.398" x2="12.065" y2="9.398" width="0.1524" layer="51"/>
<wire x1="12.065" y1="9.398" x2="10.5156" y2="9.398" width="0.1524" layer="51"/>
<wire x1="10.5156" y1="9.398" x2="10.5156" y2="10.5156" width="0.1524" layer="51"/>
<wire x1="-10.5156" y1="10.5156" x2="-9.398" y2="10.5156" width="0.1524" layer="51"/>
<wire x1="-9.398" y1="10.5156" x2="-9.398" y2="12.065" width="0.1524" layer="51"/>
<wire x1="-9.398" y1="12.065" x2="9.398" y2="12.065" width="0.1524" layer="51"/>
<wire x1="9.398" y1="12.065" x2="9.398" y2="10.5156" width="0.1524" layer="51"/>
<wire x1="9.398" y1="10.5156" x2="10.5156" y2="10.5156" width="0.1524" layer="51"/>
<wire x1="-10.5156" y1="-10.5156" x2="-9.398" y2="-10.5156" width="0.1524" layer="51"/>
<wire x1="-9.398" y1="-10.5156" x2="-9.398" y2="-12.065" width="0.1524" layer="51"/>
<wire x1="-9.398" y1="-12.065" x2="9.398" y2="-12.065" width="0.1524" layer="51"/>
<wire x1="9.398" y1="-12.065" x2="9.398" y2="-10.5156" width="0.1524" layer="51"/>
<wire x1="9.398" y1="-10.5156" x2="10.5156" y2="-10.5156" width="0.1524" layer="51"/>
<polygon width="0.1524" layer="51">
<vertex x="-10.5029" y="-10.5029"/>
<vertex x="-10.5029" y="-9.3977"/>
<vertex x="-12.065" y="-9.3977"/>
<vertex x="-12.065" y="9.3977"/>
<vertex x="-10.5029" y="9.3977"/>
<vertex x="-10.5029" y="10.5029"/>
<vertex x="-9.3977" y="10.5029"/>
<vertex x="-9.3977" y="12.065"/>
<vertex x="9.3977" y="12.065"/>
<vertex x="9.3977" y="10.5029"/>
<vertex x="10.5029" y="10.5029"/>
<vertex x="10.5029" y="9.3977"/>
<vertex x="12.065" y="9.3977"/>
<vertex x="12.065" y="-9.3977"/>
<vertex x="10.5029" y="-9.3977"/>
<vertex x="10.5029" y="-10.5029"/>
<vertex x="9.3977" y="-10.5029"/>
<vertex x="9.3977" y="-12.065"/>
<vertex x="-9.3977" y="-12.065"/>
<vertex x="-9.3977" y="-10.5029"/>
</polygon>
<wire x1="10.668" y1="8.7376" x2="10.9982" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="13.589" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.7376" x2="13.97" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.668" y1="8.255" x2="13.589" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.255" x2="13.97" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.7376" x2="13.589" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.255" x2="13.589" y2="6.985" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.7376" x2="13.462" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.7376" x2="13.716" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.462" y1="8.9916" x2="13.716" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.255" x2="13.462" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.589" y1="8.255" x2="13.716" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.462" y1="8.001" x2="13.716" y2="8.001" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="8.7376" x2="10.2362" y2="13.589" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.589" x2="10.2362" y2="13.97" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="10.9982" y2="13.589" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.589" x2="8.9662" y2="13.589" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.589" x2="12.2682" y2="13.589" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.589" x2="9.9822" y2="13.716" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.589" x2="9.9822" y2="13.462" width="0.1524" layer="20"/>
<wire x1="9.9822" y1="13.716" x2="9.9822" y2="13.462" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.589" x2="11.2522" y2="13.716" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.589" x2="11.2522" y2="13.462" width="0.1524" layer="20"/>
<wire x1="11.2522" y1="13.716" x2="11.2522" y2="13.462" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="8.7376" x2="-10.9982" y2="15.494" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.494" x2="-10.9982" y2="15.875" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.589" x2="10.9982" y2="15.494" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.494" x2="10.9982" y2="15.875" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.494" x2="10.9982" y2="15.494" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.494" x2="-10.7442" y2="15.621" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.494" x2="-10.7442" y2="15.367" width="0.1524" layer="20"/>
<wire x1="-10.7442" y1="15.621" x2="-10.7442" y2="15.367" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.494" x2="10.7442" y2="15.621" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.494" x2="10.7442" y2="15.367" width="0.1524" layer="20"/>
<wire x1="10.7442" y1="15.621" x2="10.7442" y2="15.367" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-8.7376" x2="-10.0076" y2="-13.589" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.589" x2="-10.0076" y2="-13.97" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-8.7376" x2="10.0076" y2="-13.589" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.589" x2="10.0076" y2="-13.97" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.589" x2="10.0076" y2="-13.589" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.589" x2="-9.7536" y2="-13.462" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.589" x2="-9.7536" y2="-13.716" width="0.1524" layer="20"/>
<wire x1="-9.7536" y1="-13.462" x2="-9.7536" y2="-13.716" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.589" x2="9.7536" y2="-13.462" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.589" x2="9.7536" y2="-13.716" width="0.1524" layer="20"/>
<wire x1="9.7536" y1="-13.462" x2="9.7536" y2="-13.716" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="10.0076" x2="-13.589" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="10.0076" x2="-13.97" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="-10.0076" x2="-13.589" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="-10.0076" x2="-13.97" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="10.0076" x2="-13.589" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="10.0076" x2="-13.716" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="10.0076" x2="-13.462" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.716" y1="9.7536" x2="-13.462" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="-10.0076" x2="-13.716" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.589" y1="-10.0076" x2="-13.462" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.716" y1="-9.7536" x2="-13.462" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="10.9982" x2="15.494" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="15.494" y1="10.9982" x2="15.875" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="-10.9982" x2="15.494" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.494" y1="-10.9982" x2="15.875" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.494" y1="10.9982" x2="15.494" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.494" y1="10.9982" x2="15.367" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.494" y1="10.9982" x2="15.621" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.367" y1="10.7442" x2="15.621" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.494" y1="-10.9982" x2="15.367" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.494" y1="-10.9982" x2="15.621" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.367" y1="-10.7442" x2="15.621" y2="-10.7442" width="0.1524" layer="20"/>
<text x="-16.7386" y="-17.399" size="1.27" layer="20" ratio="6" rot="SR0">Default Horiz Padstyle: r28_178</text>
<text x="-16.1798" y="-18.923" size="1.27" layer="20" ratio="6" rot="SR0">Default Vert Padstyle: r28_178</text>
<text x="-14.8082" y="-23.495" size="1.27" layer="20" ratio="6" rot="SR0">Alt 1 Padstyle: b152_229h76</text>
<text x="-14.8082" y="-25.019" size="1.27" layer="20" ratio="6" rot="SR0">Alt 2 Padstyle: b229_152h76</text>
<text x="14.097" y="8.1788" size="0.635" layer="20" ratio="4" rot="SR0">0.02in/0.5mm</text>
<text x="6.858" y="14.097" size="0.635" layer="20" ratio="4" rot="SR0">0.03in/0.762mm</text>
<text x="-4.318" y="16.002" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<text x="-4.0386" y="-14.732" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="-22.1742" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="16.002" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<wire x1="8.6106" y1="10.0076" x2="8.89" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.0076" x2="8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.9982" x2="8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="10.9982" x2="8.6106" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.0076" x2="8.382" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.0076" x2="8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.9982" x2="8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.9982" x2="8.1026" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="9.9822" x2="7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="9.9822" x2="7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="10.9982" x2="7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="10.9982" x2="7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.112" y1="9.9822" x2="7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="9.9822" x2="7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="10.9982" x2="7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="10.9982" x2="7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.604" y1="9.9822" x2="6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="9.9822" x2="6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="10.9982" x2="6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="10.9982" x2="6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="9.9822" x2="6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="9.9822" x2="6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="10.9982" x2="6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="10.9982" x2="6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="9.9822" x2="5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="9.9822" x2="5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="10.9982" x2="5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="10.9982" x2="5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="9.9822" x2="5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="9.9822" x2="5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="10.9982" x2="5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="10.9982" x2="5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="9.9822" x2="4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="9.9822" x2="4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="10.9982" x2="4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="10.9982" x2="4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="9.9822" x2="4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="9.9822" x2="4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="10.9982" x2="4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="10.9982" x2="4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="9.9822" x2="3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="9.9822" x2="3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="10.9982" x2="3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="10.9982" x2="3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="9.9822" x2="3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="9.9822" x2="3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="10.9982" x2="3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="10.9982" x2="3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="9.9822" x2="2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="9.9822" x2="2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="10.9982" x2="2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="10.9982" x2="2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="9.9822" x2="2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="9.9822" x2="2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="10.9982" x2="2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="10.9982" x2="2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="9.9822" x2="1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="9.9822" x2="1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="10.9982" x2="1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="10.9982" x2="1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="9.9822" x2="1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.397" y1="9.9822" x2="1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="10.9982" x2="1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="10.9982" x2="1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="9.9822" x2="0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.889" y1="9.9822" x2="0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="10.9982" x2="0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="10.9982" x2="0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="9.9822" x2="0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.381" y1="9.9822" x2="0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="10.9982" x2="0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="10.9982" x2="0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="9.9822" x2="-0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="9.9822" x2="-0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="10.9982" x2="-0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="10.9982" x2="-0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="9.9822" x2="-0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="9.9822" x2="-0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="10.9982" x2="-0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="10.9982" x2="-0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="9.9822" x2="-1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="9.9822" x2="-1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="10.9982" x2="-1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="10.9982" x2="-1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="9.9822" x2="-1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="9.9822" x2="-1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="10.9982" x2="-1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="10.9982" x2="-1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="9.9822" x2="-2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="9.9822" x2="-2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="10.9982" x2="-2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="10.9982" x2="-2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="9.9822" x2="-2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="9.9822" x2="-2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="10.9982" x2="-2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="10.9982" x2="-2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="9.9822" x2="-3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="9.9822" x2="-3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="10.9982" x2="-3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="10.9982" x2="-3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="9.9822" x2="-3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="9.9822" x2="-3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="10.9982" x2="-3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="10.9982" x2="-3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="9.9822" x2="-4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="9.9822" x2="-4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="10.9982" x2="-4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="10.9982" x2="-4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="9.9822" x2="-4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="9.9822" x2="-4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="10.9982" x2="-4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="10.9982" x2="-4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="9.9822" x2="-5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="9.9822" x2="-5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="10.9982" x2="-5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="10.9982" x2="-5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="9.9822" x2="-5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="9.9822" x2="-5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="10.9982" x2="-5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="10.9982" x2="-5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="9.9822" x2="-6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="9.9822" x2="-6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="10.9982" x2="-6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="10.9982" x2="-6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="9.9822" x2="-6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="9.9822" x2="-6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="10.9982" x2="-6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="10.9982" x2="-6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="9.9822" x2="-7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="9.9822" x2="-7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="10.9982" x2="-7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="10.9982" x2="-7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="9.9822" x2="-7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="9.9822" x2="-7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="10.9982" x2="-7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="10.9982" x2="-7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="9.9822" x2="-8.1026" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="9.9822" x2="-8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="10.9982" x2="-8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="10.9982" x2="-8.382" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="9.9822" x2="-8.6106" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="9.9822" x2="-8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="10.9982" x2="-8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="10.9982" x2="-8.89" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.6106" x2="-10.0076" y2="8.7376" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-10.0076" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.89" x2="-10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.89" x2="-10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.6106" x2="-10.0076" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.1026" x2="-10.0076" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.382" x2="-10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.382" x2="-10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.1026" x2="-10.0076" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.62" x2="-10.0076" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.8994" x2="-10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.8994" x2="-10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.62" x2="-10.0076" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.112" x2="-9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.3914" x2="-10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.3914" x2="-10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.112" x2="-9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.604" x2="-9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.8834" x2="-10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.8834" x2="-10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.604" x2="-9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.1214" x2="-9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.4008" x2="-10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.4008" x2="-10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.1214" x2="-9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.6134" x2="-9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.8928" x2="-10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.8928" x2="-10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.6134" x2="-9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.1054" x2="-9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.3848" x2="-10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.3848" x2="-10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.1054" x2="-9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.6228" x2="-9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.9022" x2="-10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.9022" x2="-10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.6228" x2="-9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.1148" x2="-9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.3942" x2="-10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.3942" x2="-10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.1148" x2="-9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.6068" x2="-9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.8862" x2="-10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.8862" x2="-10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.6068" x2="-9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.0988" x2="-9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.3782" x2="-10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.3782" x2="-10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.0988" x2="-9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.6162" x2="-9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.8956" x2="-10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.8956" x2="-10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.6162" x2="-9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.1082" x2="-9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.3876" x2="-10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.3876" x2="-10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.1082" x2="-9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.6002" x2="-9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.8796" x2="-10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.8796" x2="-10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.6002" x2="-9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.1176" x2="-9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.397" x2="-10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.397" x2="-10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.1176" x2="-9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.6096" x2="-9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.889" x2="-10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.889" x2="-10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.6096" x2="-9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.1016" x2="-9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.381" x2="-10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.381" x2="-10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.1016" x2="-9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.381" x2="-9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.1016" x2="-10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.1016" x2="-10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.381" x2="-9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.889" x2="-9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.6096" x2="-10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.6096" x2="-10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.889" x2="-9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.397" x2="-9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.1176" x2="-10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.1176" x2="-10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.397" x2="-9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.8796" x2="-9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.6002" x2="-10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.6002" x2="-10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.8796" x2="-9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.3876" x2="-9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.1082" x2="-10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.1082" x2="-10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.3876" x2="-9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.8956" x2="-9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.6162" x2="-10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.6162" x2="-10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.8956" x2="-9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.3782" x2="-9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.0988" x2="-10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.0988" x2="-10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.3782" x2="-9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.8862" x2="-9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.6068" x2="-10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.6068" x2="-10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.8862" x2="-9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.3942" x2="-9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.1148" x2="-10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.1148" x2="-10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.3942" x2="-9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.9022" x2="-9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.6228" x2="-10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.6228" x2="-10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.9022" x2="-9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.3848" x2="-9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.1054" x2="-10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.1054" x2="-10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.3848" x2="-9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.8928" x2="-9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.6134" x2="-10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.6134" x2="-10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.8928" x2="-9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.4008" x2="-9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.1214" x2="-10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.1214" x2="-10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.4008" x2="-9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.8834" x2="-9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.604" x2="-10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.604" x2="-10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.8834" x2="-9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.3914" x2="-9.9822" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.112" x2="-10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.112" x2="-10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.3914" x2="-9.9822" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.8994" x2="-9.9822" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.62" x2="-10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.62" x2="-10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.8994" x2="-9.9822" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.382" x2="-9.9822" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.1026" x2="-10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.1026" x2="-10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.382" x2="-9.9822" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.89" x2="-9.9822" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.6106" x2="-10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.6106" x2="-10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.89" x2="-9.9822" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.0076" x2="-8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.0076" x2="-8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.9982" x2="-8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.9982" x2="-8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.0076" x2="-8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.0076" x2="-8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.9982" x2="-8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.9982" x2="-8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.0076" x2="-7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.0076" x2="-7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.9982" x2="-7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.9982" x2="-7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.0076" x2="-7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.0076" x2="-7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.9982" x2="-7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.9982" x2="-7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.0076" x2="-6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.0076" x2="-6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.9982" x2="-6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.9982" x2="-6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.0076" x2="-6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.0076" x2="-6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.9982" x2="-6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.9982" x2="-6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.0076" x2="-5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.0076" x2="-5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.9982" x2="-5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.9982" x2="-5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.0076" x2="-5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.0076" x2="-5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.9982" x2="-5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.9982" x2="-5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.0076" x2="-4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.0076" x2="-4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.9982" x2="-4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.9982" x2="-4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.0076" x2="-4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.0076" x2="-4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.9982" x2="-4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.9982" x2="-4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.0076" x2="-3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.0076" x2="-3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.9982" x2="-3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.9982" x2="-3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.0076" x2="-3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.0076" x2="-3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.9982" x2="-3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.9982" x2="-3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.0076" x2="-2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.0076" x2="-2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.9982" x2="-2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.9982" x2="-2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.0076" x2="-2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.0076" x2="-2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.9982" x2="-2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.9982" x2="-2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.0076" x2="-1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.0076" x2="-1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.9982" x2="-1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.9982" x2="-1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.0076" x2="-1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.0076" x2="-1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.9982" x2="-1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.9982" x2="-1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.0076" x2="-0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.0076" x2="-0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.9982" x2="-0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.9982" x2="-0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.0076" x2="-0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.0076" x2="-0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.9982" x2="-0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.9982" x2="-0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.0076" x2="0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.0076" x2="0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.9982" x2="0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.9982" x2="0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.0076" x2="0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.0076" x2="0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.9982" x2="0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.9982" x2="0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.0076" x2="1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.0076" x2="1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.9982" x2="1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.9982" x2="1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.0076" x2="1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.0076" x2="1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.9982" x2="1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.9982" x2="1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.0076" x2="2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.0076" x2="2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.9982" x2="2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.9982" x2="2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.0076" x2="2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.0076" x2="2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.9982" x2="2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.9982" x2="2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.0076" x2="3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.0076" x2="3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.9982" x2="3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.9982" x2="3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.0076" x2="3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.0076" x2="3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.9982" x2="3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.9982" x2="3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.0076" x2="4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.0076" x2="4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.9982" x2="4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.9982" x2="4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.0076" x2="4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.0076" x2="4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.9982" x2="4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.9982" x2="4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.0076" x2="5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.0076" x2="5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.9982" x2="5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.9982" x2="5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.0076" x2="5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.0076" x2="5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.9982" x2="5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.9982" x2="5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.0076" x2="6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.0076" x2="6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.9982" x2="6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.9982" x2="6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.0076" x2="6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.0076" x2="6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.9982" x2="6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.9982" x2="6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.0076" x2="7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.0076" x2="7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.9982" x2="7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.9982" x2="7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.0076" x2="7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.0076" x2="7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.9982" x2="7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.9982" x2="7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.0076" x2="8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.0076" x2="8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.9982" x2="8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.9982" x2="8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.0076" x2="8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.0076" x2="8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.9982" x2="8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.9982" x2="8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.6106" x2="10.0076" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.89" x2="10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.89" x2="10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.6106" x2="10.0076" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.1026" x2="10.0076" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.382" x2="10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.382" x2="10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.1026" x2="10.0076" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.62" x2="10.0076" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.8994" x2="10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.8994" x2="10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.62" x2="10.0076" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.112" x2="10.0076" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.3914" x2="10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.3914" x2="10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.112" x2="10.0076" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.604" x2="9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.8834" x2="10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.8834" x2="10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.604" x2="9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.1214" x2="9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.4008" x2="10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.4008" x2="10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.1214" x2="9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.6134" x2="9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.8928" x2="10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.8928" x2="10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.6134" x2="9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.1054" x2="9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.3848" x2="10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.3848" x2="10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.1054" x2="9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.6228" x2="9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.9022" x2="10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.9022" x2="10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.6228" x2="9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.1148" x2="9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.3942" x2="10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.3942" x2="10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.1148" x2="9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.6068" x2="9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.8862" x2="10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.8862" x2="10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.6068" x2="9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.0988" x2="9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.3782" x2="10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.3782" x2="10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.0988" x2="9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.6162" x2="9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.8956" x2="10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.8956" x2="10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.6162" x2="9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.1082" x2="9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.3876" x2="10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.3876" x2="10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.1082" x2="9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.6002" x2="9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.8796" x2="10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.8796" x2="10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.6002" x2="9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.1176" x2="9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.397" x2="10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.397" x2="10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.1176" x2="9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.6096" x2="9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.889" x2="10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.889" x2="10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.6096" x2="9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.1016" x2="9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.381" x2="10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.381" x2="10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.1016" x2="9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.381" x2="9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.1016" x2="10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.1016" x2="10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.381" x2="9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.889" x2="9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.6096" x2="10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.6096" x2="10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.889" x2="9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.397" x2="9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.1176" x2="10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.1176" x2="10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.397" x2="9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.8796" x2="9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.6002" x2="10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.6002" x2="10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.8796" x2="9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.3876" x2="9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.1082" x2="10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.1082" x2="10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.3876" x2="9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.8956" x2="9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.6162" x2="10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.6162" x2="10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.8956" x2="9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.3782" x2="9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.0988" x2="10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.0988" x2="10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.3782" x2="9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.8862" x2="9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.6068" x2="10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.6068" x2="10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.8862" x2="9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.3942" x2="9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.1148" x2="10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.1148" x2="10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.3942" x2="9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.9022" x2="9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.6228" x2="10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.6228" x2="10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.9022" x2="9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.3848" x2="9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.1054" x2="10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.1054" x2="10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.3848" x2="9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.8928" x2="9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.6134" x2="10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.6134" x2="10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.8928" x2="9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.4008" x2="9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.1214" x2="10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.1214" x2="10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.4008" x2="9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.8834" x2="9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.604" x2="10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.604" x2="10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.8834" x2="9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.3914" x2="9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.112" x2="10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.112" x2="10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.3914" x2="9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.8994" x2="9.9822" y2="7.62" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.62" x2="10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.62" x2="10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.8994" x2="9.9822" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.382" x2="9.9822" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.1026" x2="10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.1026" x2="10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.382" x2="9.9822" y2="8.382" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.89" x2="9.9822" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.6106" x2="10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.6106" x2="10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.89" x2="9.9822" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-8.7376" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="-10.0076" x2="10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-10.0076" x2="10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="10.0076" x2="-10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="10.0076" x2="-10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<text x="-10.1854" y="8.3566" size="1.27" layer="51" ratio="6" rot="SR0">*</text>
<wire x1="-0.254" y1="0" x2="0.254" y2="0" width="0.1524" layer="23"/>
<wire x1="0" y1="-0.254" x2="0" y2="0.254" width="0.1524" layer="23"/>
<text x="-3.2766" y="-0.635" size="1.27" layer="25" ratio="6" rot="SR0">&gt;Name</text>
</package>
<package name="TQFP144-L">
<smd name="1" x="-10.5664" y="8.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="2" x="-10.5664" y="8.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="3" x="-10.5664" y="7.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="4" x="-10.5664" y="7.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="5" x="-10.5664" y="6.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="6" x="-10.5664" y="6.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="7" x="-10.5664" y="5.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="8" x="-10.5664" y="5.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="9" x="-10.5664" y="4.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="10" x="-10.5664" y="4.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="11" x="-10.5664" y="3.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="12" x="-10.5664" y="3.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="13" x="-10.5664" y="2.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="14" x="-10.5664" y="2.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="15" x="-10.5664" y="1.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="16" x="-10.5664" y="1.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="17" x="-10.5664" y="0.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="18" x="-10.5664" y="0.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="19" x="-10.5664" y="-0.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="20" x="-10.5664" y="-0.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="21" x="-10.5664" y="-1.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="22" x="-10.5664" y="-1.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="23" x="-10.5664" y="-2.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="24" x="-10.5664" y="-2.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="25" x="-10.5664" y="-3.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="26" x="-10.5664" y="-3.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="27" x="-10.5664" y="-4.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="28" x="-10.5664" y="-4.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="29" x="-10.5664" y="-5.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="30" x="-10.5664" y="-5.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="31" x="-10.5664" y="-6.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="32" x="-10.5664" y="-6.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="33" x="-10.5664" y="-7.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="34" x="-10.5664" y="-7.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="35" x="-10.5664" y="-8.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="36" x="-10.5664" y="-8.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="37" x="-8.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="38" x="-8.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="39" x="-7.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="40" x="-7.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="41" x="-6.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="42" x="-6.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="43" x="-5.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="44" x="-5.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="45" x="-4.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="46" x="-4.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="47" x="-3.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="48" x="-3.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="49" x="-2.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="50" x="-2.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="51" x="-1.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="52" x="-1.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="53" x="-0.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="54" x="-0.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="55" x="0.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="56" x="0.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="57" x="1.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="58" x="1.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="59" x="2.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="60" x="2.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="61" x="3.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="62" x="3.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="63" x="4.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="64" x="4.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="65" x="5.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="66" x="5.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="67" x="6.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="68" x="6.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="69" x="7.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="70" x="7.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="71" x="8.25" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="72" x="8.75" y="-10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="73" x="10.5664" y="-8.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="74" x="10.5664" y="-8.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="75" x="10.5664" y="-7.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="76" x="10.5664" y="-7.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="77" x="10.5664" y="-6.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="78" x="10.5664" y="-6.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="79" x="10.5664" y="-5.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="80" x="10.5664" y="-5.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="81" x="10.5664" y="-4.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="82" x="10.5664" y="-4.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="83" x="10.5664" y="-3.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="84" x="10.5664" y="-3.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="85" x="10.5664" y="-2.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="86" x="10.5664" y="-2.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="87" x="10.5664" y="-1.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="88" x="10.5664" y="-1.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="89" x="10.5664" y="-0.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="90" x="10.5664" y="-0.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="91" x="10.5664" y="0.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="92" x="10.5664" y="0.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="93" x="10.5664" y="1.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="94" x="10.5664" y="1.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="95" x="10.5664" y="2.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="96" x="10.5664" y="2.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="97" x="10.5664" y="3.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="98" x="10.5664" y="3.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="99" x="10.5664" y="4.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="100" x="10.5664" y="4.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="101" x="10.5664" y="5.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="102" x="10.5664" y="5.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="103" x="10.5664" y="6.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="104" x="10.5664" y="6.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="105" x="10.5664" y="7.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="106" x="10.5664" y="7.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="107" x="10.5664" y="8.25" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="108" x="10.5664" y="8.75" dx="0.2794" dy="1.1684" layer="1" rot="R270"/>
<smd name="109" x="8.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="110" x="8.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="111" x="7.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="112" x="7.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="113" x="6.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="114" x="6.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="115" x="5.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="116" x="5.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="117" x="4.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="118" x="4.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="119" x="3.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="120" x="3.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="121" x="2.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="122" x="2.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="123" x="1.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="124" x="1.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="125" x="0.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="126" x="0.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="127" x="-0.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="128" x="-0.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="129" x="-1.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="130" x="-1.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="131" x="-2.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="132" x="-2.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="133" x="-3.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="134" x="-3.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="135" x="-4.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="136" x="-4.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="137" x="-5.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="138" x="-5.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="139" x="-6.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="140" x="-6.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="141" x="-7.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="142" x="-7.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="143" x="-8.25" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<smd name="144" x="-8.75" y="10.5664" dx="0.2794" dy="1.1684" layer="1" rot="R180"/>
<wire x1="-10.1092" y1="-10.1092" x2="-9.2202" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="-10.1092" x2="10.1092" y2="-9.2202" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="10.1092" x2="9.2202" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="10.1092" x2="-10.1092" y2="9.2202" width="0.1524" layer="21"/>
<wire x1="-10.1092" y1="-9.2202" x2="-10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="9.2202" y1="-10.1092" x2="10.1092" y2="-10.1092" width="0.1524" layer="21"/>
<wire x1="10.1092" y1="9.2202" x2="10.1092" y2="10.1092" width="0.1524" layer="21"/>
<wire x1="-9.2202" y1="10.1092" x2="-10.1092" y2="10.1092" width="0.1524" layer="21"/>
<polygon width="0.0254" layer="21">
<vertex x="-11.6586" y="4.4405"/>
<vertex x="-11.6586" y="4.0595"/>
<vertex x="-11.4046" y="4.0595"/>
<vertex x="-11.4046" y="4.4405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-11.6586" y="-0.5595"/>
<vertex x="-11.6586" y="-0.9405"/>
<vertex x="-11.4046" y="-0.9405"/>
<vertex x="-11.4046" y="-0.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-11.6586" y="-5.5595"/>
<vertex x="-11.6586" y="-5.9405"/>
<vertex x="-11.4046" y="-5.9405"/>
<vertex x="-11.4046" y="-5.5595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-7.4405" y="-11.4046"/>
<vertex x="-7.4405" y="-11.6586"/>
<vertex x="-7.0595" y="-11.6586"/>
<vertex x="-7.0595" y="-11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-2.4405" y="-11.4046"/>
<vertex x="-2.4405" y="-11.6586"/>
<vertex x="-2.0595" y="-11.6586"/>
<vertex x="-2.0595" y="-11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="2.5595" y="-11.4046"/>
<vertex x="2.5595" y="-11.6586"/>
<vertex x="2.9405" y="-11.6586"/>
<vertex x="2.9405" y="-11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="7.5595" y="-11.4046"/>
<vertex x="7.5595" y="-11.6586"/>
<vertex x="7.9405" y="-11.6586"/>
<vertex x="7.9405" y="-11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.6586" y="-5.0595"/>
<vertex x="11.6586" y="-5.4405"/>
<vertex x="11.4046" y="-5.4405"/>
<vertex x="11.4046" y="-5.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.6586" y="-0.0595"/>
<vertex x="11.6586" y="-0.4405"/>
<vertex x="11.4046" y="-0.4405"/>
<vertex x="11.4046" y="-0.0595"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="11.6586" y="4.9405"/>
<vertex x="11.6586" y="4.5595"/>
<vertex x="11.4046" y="4.5595"/>
<vertex x="11.4046" y="4.9405"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="8.0595" y="11.4046"/>
<vertex x="8.0595" y="11.6586"/>
<vertex x="8.4405" y="11.6586"/>
<vertex x="8.4405" y="11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="3.0595" y="11.4046"/>
<vertex x="3.0595" y="11.6586"/>
<vertex x="3.4405" y="11.6586"/>
<vertex x="3.4405" y="11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-1.9405" y="11.4046"/>
<vertex x="-1.9405" y="11.6586"/>
<vertex x="-1.5595" y="11.6586"/>
<vertex x="-1.5595" y="11.4046"/>
</polygon>
<polygon width="0.0254" layer="21">
<vertex x="-6.9405" y="11.4046"/>
<vertex x="-6.9405" y="11.6586"/>
<vertex x="-6.5595" y="11.6586"/>
<vertex x="-6.5595" y="11.4046"/>
</polygon>
<text x="-12.3698" y="8.7376" size="1.27" layer="21" ratio="6" rot="SR0">*</text>
<wire x1="-10.1092" y1="-10.1092" x2="-10.1092" y2="-8.9916" width="0.1524" layer="51"/>
<wire x1="-10.1092" y1="-8.9916" x2="-11.2522" y2="-8.9916" width="0.1524" layer="51"/>
<wire x1="-11.2522" y1="-8.9916" x2="-11.2522" y2="8.9916" width="0.1524" layer="51"/>
<wire x1="-11.2522" y1="8.9916" x2="-10.1092" y2="8.9916" width="0.1524" layer="51"/>
<wire x1="-10.1092" y1="8.9916" x2="-10.1092" y2="10.1092" width="0.1524" layer="51"/>
<wire x1="10.1092" y1="-10.1092" x2="10.1092" y2="-8.9916" width="0.1524" layer="51"/>
<wire x1="10.1092" y1="-8.9916" x2="11.2522" y2="-8.9916" width="0.1524" layer="51"/>
<wire x1="11.2522" y1="-8.9916" x2="11.2522" y2="8.9916" width="0.1524" layer="51"/>
<wire x1="11.2522" y1="8.9916" x2="10.1092" y2="8.9916" width="0.1524" layer="51"/>
<wire x1="10.1092" y1="8.9916" x2="10.1092" y2="10.1092" width="0.1524" layer="51"/>
<wire x1="-10.1092" y1="10.1092" x2="-8.9916" y2="10.1092" width="0.1524" layer="51"/>
<wire x1="-8.9916" y1="10.1092" x2="-8.9916" y2="11.2522" width="0.1524" layer="51"/>
<wire x1="-8.9916" y1="11.2522" x2="8.9916" y2="11.2522" width="0.1524" layer="51"/>
<wire x1="8.9916" y1="11.2522" x2="8.9916" y2="10.1092" width="0.1524" layer="51"/>
<wire x1="8.9916" y1="10.1092" x2="10.1092" y2="10.1092" width="0.1524" layer="51"/>
<wire x1="-10.1092" y1="-10.1092" x2="-8.9916" y2="-10.1092" width="0.1524" layer="51"/>
<wire x1="-8.9916" y1="-10.1092" x2="-8.9916" y2="-11.2522" width="0.1524" layer="51"/>
<wire x1="-8.9916" y1="-11.2522" x2="8.9916" y2="-11.2522" width="0.1524" layer="51"/>
<wire x1="8.9916" y1="-11.2522" x2="8.9916" y2="-10.1092" width="0.1524" layer="51"/>
<wire x1="8.9916" y1="-10.1092" x2="10.1092" y2="-10.1092" width="0.1524" layer="51"/>
<polygon width="0.1524" layer="51">
<vertex x="-10.0965" y="-10.0965"/>
<vertex x="-10.0965" y="-8.9913"/>
<vertex x="-11.2522" y="-8.9913"/>
<vertex x="-11.2522" y="8.9913"/>
<vertex x="-10.0965" y="8.9913"/>
<vertex x="-10.0965" y="10.0965"/>
<vertex x="-8.9913" y="10.0965"/>
<vertex x="-8.9913" y="11.2522"/>
<vertex x="8.9913" y="11.2522"/>
<vertex x="8.9913" y="10.0965"/>
<vertex x="10.0965" y="10.0965"/>
<vertex x="10.0965" y="8.9913"/>
<vertex x="11.2522" y="8.9913"/>
<vertex x="11.2522" y="-8.9913"/>
<vertex x="10.0965" y="-8.9913"/>
<vertex x="10.0965" y="-10.0965"/>
<vertex x="8.9913" y="-10.0965"/>
<vertex x="8.9913" y="-11.2522"/>
<vertex x="-8.9913" y="-11.2522"/>
<vertex x="-8.9913" y="-10.0965"/>
</polygon>
<wire x1="10.5664" y1="8.7376" x2="10.9982" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="13.4874" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.7376" x2="13.8684" y2="8.7376" width="0.1524" layer="20"/>
<wire x1="10.5664" y1="8.255" x2="13.4874" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.255" x2="13.8684" y2="8.255" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.7376" x2="13.4874" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.255" x2="13.4874" y2="6.985" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.7376" x2="13.3604" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.7376" x2="13.6144" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.3604" y1="8.9916" x2="13.6144" y2="8.9916" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.255" x2="13.3604" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.4874" y1="8.255" x2="13.6144" y2="8.001" width="0.1524" layer="20"/>
<wire x1="13.3604" y1="8.001" x2="13.6144" y2="8.001" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="8.7376" x2="10.2362" y2="13.4874" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.4874" x2="10.2362" y2="13.8684" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="8.7376" x2="10.9982" y2="13.4874" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.4874" x2="8.9662" y2="13.4874" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.4874" x2="12.2682" y2="13.4874" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.4874" x2="9.9822" y2="13.6144" width="0.1524" layer="20"/>
<wire x1="10.2362" y1="13.4874" x2="9.9822" y2="13.3604" width="0.1524" layer="20"/>
<wire x1="9.9822" y1="13.6144" x2="9.9822" y2="13.3604" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.4874" x2="11.2522" y2="13.6144" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.4874" x2="11.2522" y2="13.3604" width="0.1524" layer="20"/>
<wire x1="11.2522" y1="13.6144" x2="11.2522" y2="13.3604" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="8.7376" x2="-10.9982" y2="15.3924" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.3924" x2="-10.9982" y2="15.7734" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="13.4874" x2="10.9982" y2="15.3924" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.3924" x2="10.9982" y2="15.7734" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.3924" x2="10.9982" y2="15.3924" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.3924" x2="-10.7442" y2="15.5194" width="0.1524" layer="20"/>
<wire x1="-10.9982" y1="15.3924" x2="-10.7442" y2="15.2654" width="0.1524" layer="20"/>
<wire x1="-10.7442" y1="15.5194" x2="-10.7442" y2="15.2654" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.3924" x2="10.7442" y2="15.5194" width="0.1524" layer="20"/>
<wire x1="10.9982" y1="15.3924" x2="10.7442" y2="15.2654" width="0.1524" layer="20"/>
<wire x1="10.7442" y1="15.5194" x2="10.7442" y2="15.2654" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-8.7376" x2="-10.0076" y2="-13.4874" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.4874" x2="-10.0076" y2="-13.8684" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-8.7376" x2="10.0076" y2="-13.4874" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.4874" x2="10.0076" y2="-13.8684" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.4874" x2="10.0076" y2="-13.4874" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.4874" x2="-9.7536" y2="-13.3604" width="0.1524" layer="20"/>
<wire x1="-10.0076" y1="-13.4874" x2="-9.7536" y2="-13.6144" width="0.1524" layer="20"/>
<wire x1="-9.7536" y1="-13.3604" x2="-9.7536" y2="-13.6144" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.4874" x2="9.7536" y2="-13.3604" width="0.1524" layer="20"/>
<wire x1="10.0076" y1="-13.4874" x2="9.7536" y2="-13.6144" width="0.1524" layer="20"/>
<wire x1="9.7536" y1="-13.3604" x2="9.7536" y2="-13.6144" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="10.0076" x2="-13.4874" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="10.0076" x2="-13.8684" y2="10.0076" width="0.1524" layer="20"/>
<wire x1="-8.7376" y1="-10.0076" x2="-13.4874" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="-10.0076" x2="-13.8684" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="10.0076" x2="-13.4874" y2="-10.0076" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="10.0076" x2="-13.6144" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="10.0076" x2="-13.3604" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.6144" y1="9.7536" x2="-13.3604" y2="9.7536" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="-10.0076" x2="-13.6144" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.4874" y1="-10.0076" x2="-13.3604" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="-13.6144" y1="-9.7536" x2="-13.3604" y2="-9.7536" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="10.9982" x2="15.3924" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="10.9982" x2="15.7734" y2="10.9982" width="0.1524" layer="20"/>
<wire x1="8.7376" y1="-10.9982" x2="15.3924" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="-10.9982" x2="15.7734" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="10.9982" x2="15.3924" y2="-10.9982" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="10.9982" x2="15.2654" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="10.9982" x2="15.5194" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.2654" y1="10.7442" x2="15.5194" y2="10.7442" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="-10.9982" x2="15.2654" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.3924" y1="-10.9982" x2="15.5194" y2="-10.7442" width="0.1524" layer="20"/>
<wire x1="15.2654" y1="-10.7442" x2="15.5194" y2="-10.7442" width="0.1524" layer="20"/>
<text x="-16.7386" y="-17.2974" size="1.27" layer="20" ratio="6" rot="SR0">Default Horiz Padstyle: r28_117</text>
<text x="-16.1798" y="-18.8214" size="1.27" layer="20" ratio="6" rot="SR0">Default Vert Padstyle: r28_117</text>
<text x="-14.8082" y="-23.3934" size="1.27" layer="20" ratio="6" rot="SR0">Alt 1 Padstyle: b152_229h76</text>
<text x="-14.8082" y="-24.9174" size="1.27" layer="20" ratio="6" rot="SR0">Alt 2 Padstyle: b229_152h76</text>
<text x="13.9954" y="8.1788" size="0.635" layer="20" ratio="4" rot="SR0">0.02in/0.5mm</text>
<text x="6.858" y="13.9954" size="0.635" layer="20" ratio="4" rot="SR0">0.03in/0.762mm</text>
<text x="-4.318" y="15.9004" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<text x="-4.0386" y="-14.6304" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="-22.0726" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.787in/19.99mm</text>
<text x="15.9004" y="-0.3048" size="0.635" layer="20" ratio="4" rot="SR0">0.866in/21.996mm</text>
<wire x1="8.6106" y1="10.0076" x2="8.89" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.0076" x2="8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="10.9982" x2="8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="10.9982" x2="8.6106" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.0076" x2="8.382" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.0076" x2="8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="10.9982" x2="8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="10.9982" x2="8.1026" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="9.9822" x2="7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="9.9822" x2="7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="10.9982" x2="7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="10.9982" x2="7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.112" y1="9.9822" x2="7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="9.9822" x2="7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="10.9982" x2="7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="10.9982" x2="7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.604" y1="9.9822" x2="6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="9.9822" x2="6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="10.9982" x2="6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="10.9982" x2="6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="9.9822" x2="6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="9.9822" x2="6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="10.9982" x2="6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="10.9982" x2="6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="9.9822" x2="5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="9.9822" x2="5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="10.9982" x2="5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="10.9982" x2="5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="9.9822" x2="5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="9.9822" x2="5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="10.9982" x2="5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="10.9982" x2="5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="9.9822" x2="4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="9.9822" x2="4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="10.9982" x2="4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="10.9982" x2="4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="9.9822" x2="4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="9.9822" x2="4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="10.9982" x2="4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="10.9982" x2="4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="9.9822" x2="3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="9.9822" x2="3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="10.9982" x2="3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="10.9982" x2="3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="9.9822" x2="3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="9.9822" x2="3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="10.9982" x2="3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="10.9982" x2="3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="9.9822" x2="2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="9.9822" x2="2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="10.9982" x2="2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="10.9982" x2="2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="9.9822" x2="2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="9.9822" x2="2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="10.9982" x2="2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="10.9982" x2="2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="9.9822" x2="1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="9.9822" x2="1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="10.9982" x2="1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="10.9982" x2="1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="9.9822" x2="1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="1.397" y1="9.9822" x2="1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="10.9982" x2="1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="10.9982" x2="1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="9.9822" x2="0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.889" y1="9.9822" x2="0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="10.9982" x2="0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="10.9982" x2="0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="9.9822" x2="0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="0.381" y1="9.9822" x2="0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="10.9982" x2="0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="10.9982" x2="0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="9.9822" x2="-0.1016" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="9.9822" x2="-0.1016" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="10.9982" x2="-0.381" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="10.9982" x2="-0.381" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="9.9822" x2="-0.6096" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="9.9822" x2="-0.6096" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="10.9982" x2="-0.889" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="10.9982" x2="-0.889" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="9.9822" x2="-1.1176" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="9.9822" x2="-1.1176" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="10.9982" x2="-1.397" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="10.9982" x2="-1.397" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="9.9822" x2="-1.6002" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="9.9822" x2="-1.6002" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="10.9982" x2="-1.8796" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="10.9982" x2="-1.8796" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="9.9822" x2="-2.1082" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="9.9822" x2="-2.1082" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="10.9982" x2="-2.3876" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="10.9982" x2="-2.3876" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="9.9822" x2="-2.6162" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="9.9822" x2="-2.6162" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="10.9982" x2="-2.8956" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="10.9982" x2="-2.8956" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="9.9822" x2="-3.0988" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="9.9822" x2="-3.0988" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="10.9982" x2="-3.3782" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="10.9982" x2="-3.3782" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="9.9822" x2="-3.6068" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="9.9822" x2="-3.6068" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="10.9982" x2="-3.8862" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="10.9982" x2="-3.8862" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="9.9822" x2="-4.1148" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="9.9822" x2="-4.1148" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="10.9982" x2="-4.3942" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="10.9982" x2="-4.3942" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="9.9822" x2="-4.6228" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="9.9822" x2="-4.6228" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="10.9982" x2="-4.9022" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="10.9982" x2="-4.9022" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="9.9822" x2="-5.1054" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="9.9822" x2="-5.1054" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="10.9982" x2="-5.3848" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="10.9982" x2="-5.3848" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="9.9822" x2="-5.6134" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="9.9822" x2="-5.6134" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="10.9982" x2="-5.8928" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="10.9982" x2="-5.8928" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="9.9822" x2="-6.1214" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="9.9822" x2="-6.1214" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="10.9982" x2="-6.4008" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="10.9982" x2="-6.4008" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="9.9822" x2="-6.604" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="9.9822" x2="-6.604" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="10.9982" x2="-6.8834" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="10.9982" x2="-6.8834" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="9.9822" x2="-7.112" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="9.9822" x2="-7.112" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="10.9982" x2="-7.3914" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="10.9982" x2="-7.3914" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="9.9822" x2="-7.62" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="9.9822" x2="-7.62" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="10.9982" x2="-7.8994" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="10.9982" x2="-7.8994" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="9.9822" x2="-8.1026" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="9.9822" x2="-8.1026" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="10.9982" x2="-8.382" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="10.9982" x2="-8.382" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="9.9822" x2="-8.6106" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="9.9822" x2="-8.6106" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="10.9982" x2="-8.89" y2="10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="10.9982" x2="-8.89" y2="9.9822" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.6106" x2="-10.0076" y2="8.7376" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-10.0076" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.89" x2="-10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.89" x2="-10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.6106" x2="-10.0076" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.1026" x2="-10.0076" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.382" x2="-10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.382" x2="-10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="8.1026" x2="-10.0076" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.62" x2="-10.0076" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="7.8994" x2="-10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.8994" x2="-10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.62" x2="-10.0076" y2="7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.112" x2="-9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="7.3914" x2="-10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.3914" x2="-10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="7.112" x2="-9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.604" x2="-9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.8834" x2="-10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.8834" x2="-10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.604" x2="-9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.1214" x2="-9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="6.4008" x2="-10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.4008" x2="-10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="6.1214" x2="-9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.6134" x2="-9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.8928" x2="-10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.8928" x2="-10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.6134" x2="-9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.1054" x2="-9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="5.3848" x2="-10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.3848" x2="-10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="5.1054" x2="-9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.6228" x2="-9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.9022" x2="-10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.9022" x2="-10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.6228" x2="-9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.1148" x2="-9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="4.3942" x2="-10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.3942" x2="-10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="4.1148" x2="-9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.6068" x2="-9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.8862" x2="-10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.8862" x2="-10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.6068" x2="-9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.0988" x2="-9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="3.3782" x2="-10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.3782" x2="-10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="3.0988" x2="-9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.6162" x2="-9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.8956" x2="-10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.8956" x2="-10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.6162" x2="-9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.1082" x2="-9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="2.3876" x2="-10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.3876" x2="-10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="2.1082" x2="-9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.6002" x2="-9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.8796" x2="-10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.8796" x2="-10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.6002" x2="-9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.1176" x2="-9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="1.397" x2="-10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.397" x2="-10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="1.1176" x2="-9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.6096" x2="-9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.889" x2="-10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.889" x2="-10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.6096" x2="-9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.1016" x2="-9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="0.381" x2="-10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.381" x2="-10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="0.1016" x2="-9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.381" x2="-9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.1016" x2="-10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.1016" x2="-10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.381" x2="-9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.889" x2="-9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-0.6096" x2="-10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.6096" x2="-10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-0.889" x2="-9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.397" x2="-9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.1176" x2="-10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.1176" x2="-10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.397" x2="-9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.8796" x2="-9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-1.6002" x2="-10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.6002" x2="-10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-1.8796" x2="-9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.3876" x2="-9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.1082" x2="-10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.1082" x2="-10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.3876" x2="-9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.8956" x2="-9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-2.6162" x2="-10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.6162" x2="-10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-2.8956" x2="-9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.3782" x2="-9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.0988" x2="-10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.0988" x2="-10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.3782" x2="-9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.8862" x2="-9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-3.6068" x2="-10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.6068" x2="-10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-3.8862" x2="-9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.3942" x2="-9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.1148" x2="-10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.1148" x2="-10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.3942" x2="-9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.9022" x2="-9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-4.6228" x2="-10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.6228" x2="-10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-4.9022" x2="-9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.3848" x2="-9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.1054" x2="-10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.1054" x2="-10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.3848" x2="-9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.8928" x2="-9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-5.6134" x2="-10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.6134" x2="-10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-5.8928" x2="-9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.4008" x2="-9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.1214" x2="-10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.1214" x2="-10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.4008" x2="-9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.8834" x2="-9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-6.604" x2="-10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.604" x2="-10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-6.8834" x2="-9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.3914" x2="-9.9822" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.112" x2="-10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.112" x2="-10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.3914" x2="-9.9822" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.8994" x2="-9.9822" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-7.62" x2="-10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.62" x2="-10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-7.8994" x2="-9.9822" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.382" x2="-9.9822" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.1026" x2="-10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.1026" x2="-10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.382" x2="-9.9822" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.89" x2="-9.9822" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-9.9822" y1="-8.6106" x2="-10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.6106" x2="-10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-10.9982" y1="-8.89" x2="-9.9822" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.0076" x2="-8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.0076" x2="-8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.89" y1="-10.9982" x2="-8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.6106" y1="-10.9982" x2="-8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.0076" x2="-8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.0076" x2="-8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.382" y1="-10.9982" x2="-8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-8.1026" y1="-10.9982" x2="-8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.0076" x2="-7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.0076" x2="-7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.8994" y1="-10.9982" x2="-7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.62" y1="-10.9982" x2="-7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.0076" x2="-7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.0076" x2="-7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.3914" y1="-10.9982" x2="-7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-7.112" y1="-10.9982" x2="-7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.0076" x2="-6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.0076" x2="-6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.8834" y1="-10.9982" x2="-6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.604" y1="-10.9982" x2="-6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.0076" x2="-6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.0076" x2="-6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.4008" y1="-10.9982" x2="-6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-6.1214" y1="-10.9982" x2="-6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.0076" x2="-5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.0076" x2="-5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.8928" y1="-10.9982" x2="-5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.6134" y1="-10.9982" x2="-5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.0076" x2="-5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.0076" x2="-5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.3848" y1="-10.9982" x2="-5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-5.1054" y1="-10.9982" x2="-5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.0076" x2="-4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.0076" x2="-4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.9022" y1="-10.9982" x2="-4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.6228" y1="-10.9982" x2="-4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.0076" x2="-4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.0076" x2="-4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.3942" y1="-10.9982" x2="-4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-4.1148" y1="-10.9982" x2="-4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.0076" x2="-3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.0076" x2="-3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.8862" y1="-10.9982" x2="-3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.6068" y1="-10.9982" x2="-3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.0076" x2="-3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.0076" x2="-3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.3782" y1="-10.9982" x2="-3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-3.0988" y1="-10.9982" x2="-3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.0076" x2="-2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.0076" x2="-2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.8956" y1="-10.9982" x2="-2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.6162" y1="-10.9982" x2="-2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.0076" x2="-2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.0076" x2="-2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.3876" y1="-10.9982" x2="-2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-2.1082" y1="-10.9982" x2="-2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.0076" x2="-1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.0076" x2="-1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.8796" y1="-10.9982" x2="-1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.6002" y1="-10.9982" x2="-1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.0076" x2="-1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.0076" x2="-1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.397" y1="-10.9982" x2="-1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-1.1176" y1="-10.9982" x2="-1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.0076" x2="-0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.0076" x2="-0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.889" y1="-10.9982" x2="-0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.6096" y1="-10.9982" x2="-0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.0076" x2="-0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.0076" x2="-0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.381" y1="-10.9982" x2="-0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="-0.1016" y1="-10.9982" x2="-0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.0076" x2="0.1016" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.0076" x2="0.1016" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.1016" y1="-10.9982" x2="0.381" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.381" y1="-10.9982" x2="0.381" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.0076" x2="0.6096" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.0076" x2="0.6096" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.6096" y1="-10.9982" x2="0.889" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="0.889" y1="-10.9982" x2="0.889" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.0076" x2="1.1176" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.0076" x2="1.1176" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.1176" y1="-10.9982" x2="1.397" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.397" y1="-10.9982" x2="1.397" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.0076" x2="1.6002" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.0076" x2="1.6002" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.6002" y1="-10.9982" x2="1.8796" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="1.8796" y1="-10.9982" x2="1.8796" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.0076" x2="2.1082" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.0076" x2="2.1082" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.1082" y1="-10.9982" x2="2.3876" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.3876" y1="-10.9982" x2="2.3876" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.0076" x2="2.6162" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.0076" x2="2.6162" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.6162" y1="-10.9982" x2="2.8956" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="2.8956" y1="-10.9982" x2="2.8956" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.0076" x2="3.0988" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.0076" x2="3.0988" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.0988" y1="-10.9982" x2="3.3782" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.3782" y1="-10.9982" x2="3.3782" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.0076" x2="3.6068" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.0076" x2="3.6068" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.6068" y1="-10.9982" x2="3.8862" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="3.8862" y1="-10.9982" x2="3.8862" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.0076" x2="4.1148" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.0076" x2="4.1148" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.1148" y1="-10.9982" x2="4.3942" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.3942" y1="-10.9982" x2="4.3942" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.0076" x2="4.6228" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.0076" x2="4.6228" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.6228" y1="-10.9982" x2="4.9022" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="4.9022" y1="-10.9982" x2="4.9022" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.0076" x2="5.1054" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.0076" x2="5.1054" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.1054" y1="-10.9982" x2="5.3848" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.3848" y1="-10.9982" x2="5.3848" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.0076" x2="5.6134" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.0076" x2="5.6134" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.6134" y1="-10.9982" x2="5.8928" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="5.8928" y1="-10.9982" x2="5.8928" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.0076" x2="6.1214" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.0076" x2="6.1214" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.1214" y1="-10.9982" x2="6.4008" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.4008" y1="-10.9982" x2="6.4008" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.0076" x2="6.604" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.0076" x2="6.604" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.604" y1="-10.9982" x2="6.8834" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="6.8834" y1="-10.9982" x2="6.8834" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.0076" x2="7.112" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.0076" x2="7.112" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.112" y1="-10.9982" x2="7.3914" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.3914" y1="-10.9982" x2="7.3914" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.0076" x2="7.62" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.0076" x2="7.62" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.62" y1="-10.9982" x2="7.8994" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="7.8994" y1="-10.9982" x2="7.8994" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.0076" x2="8.1026" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.0076" x2="8.1026" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.1026" y1="-10.9982" x2="8.382" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.382" y1="-10.9982" x2="8.382" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.0076" x2="8.6106" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.0076" x2="8.6106" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.6106" y1="-10.9982" x2="8.89" y2="-10.9982" width="0.1524" layer="51"/>
<wire x1="8.89" y1="-10.9982" x2="8.89" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.6106" x2="10.0076" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.89" x2="10.9982" y2="-8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.89" x2="10.9982" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.6106" x2="10.0076" y2="-8.6106" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.1026" x2="10.0076" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-8.382" x2="10.9982" y2="-8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.382" x2="10.9982" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-8.1026" x2="10.0076" y2="-8.1026" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.62" x2="10.0076" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.8994" x2="10.9982" y2="-7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.8994" x2="10.9982" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.62" x2="10.0076" y2="-7.62" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.112" x2="10.0076" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-7.3914" x2="10.9982" y2="-7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.3914" x2="10.9982" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-7.112" x2="10.0076" y2="-7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.604" x2="9.9822" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.8834" x2="10.9982" y2="-6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.8834" x2="10.9982" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.604" x2="9.9822" y2="-6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.1214" x2="9.9822" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-6.4008" x2="10.9982" y2="-6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.4008" x2="10.9982" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-6.1214" x2="9.9822" y2="-6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.6134" x2="9.9822" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.8928" x2="10.9982" y2="-5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.8928" x2="10.9982" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.6134" x2="9.9822" y2="-5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.1054" x2="9.9822" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-5.3848" x2="10.9982" y2="-5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.3848" x2="10.9982" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-5.1054" x2="9.9822" y2="-5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.6228" x2="9.9822" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.9022" x2="10.9982" y2="-4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.9022" x2="10.9982" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.6228" x2="9.9822" y2="-4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.1148" x2="9.9822" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-4.3942" x2="10.9982" y2="-4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.3942" x2="10.9982" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-4.1148" x2="9.9822" y2="-4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.6068" x2="9.9822" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.8862" x2="10.9982" y2="-3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.8862" x2="10.9982" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.6068" x2="9.9822" y2="-3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.0988" x2="9.9822" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-3.3782" x2="10.9982" y2="-3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.3782" x2="10.9982" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-3.0988" x2="9.9822" y2="-3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.6162" x2="9.9822" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.8956" x2="10.9982" y2="-2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.8956" x2="10.9982" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.6162" x2="9.9822" y2="-2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.1082" x2="9.9822" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-2.3876" x2="10.9982" y2="-2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.3876" x2="10.9982" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-2.1082" x2="9.9822" y2="-2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.6002" x2="9.9822" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.8796" x2="10.9982" y2="-1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.8796" x2="10.9982" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.6002" x2="9.9822" y2="-1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.1176" x2="9.9822" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-1.397" x2="10.9982" y2="-1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.397" x2="10.9982" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-1.1176" x2="9.9822" y2="-1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.6096" x2="9.9822" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.889" x2="10.9982" y2="-0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.889" x2="10.9982" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.6096" x2="9.9822" y2="-0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.1016" x2="9.9822" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="-0.381" x2="10.9982" y2="-0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.381" x2="10.9982" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="-0.1016" x2="9.9822" y2="-0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.381" x2="9.9822" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.1016" x2="10.9982" y2="0.1016" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.1016" x2="10.9982" y2="0.381" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.381" x2="9.9822" y2="0.381" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.889" x2="9.9822" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="0.6096" x2="10.9982" y2="0.6096" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.6096" x2="10.9982" y2="0.889" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="0.889" x2="9.9822" y2="0.889" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.397" x2="9.9822" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.1176" x2="10.9982" y2="1.1176" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.1176" x2="10.9982" y2="1.397" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.397" x2="9.9822" y2="1.397" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.8796" x2="9.9822" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="1.6002" x2="10.9982" y2="1.6002" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.6002" x2="10.9982" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="1.8796" x2="9.9822" y2="1.8796" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.3876" x2="9.9822" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.1082" x2="10.9982" y2="2.1082" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.1082" x2="10.9982" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.3876" x2="9.9822" y2="2.3876" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.8956" x2="9.9822" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="2.6162" x2="10.9982" y2="2.6162" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.6162" x2="10.9982" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="2.8956" x2="9.9822" y2="2.8956" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.3782" x2="9.9822" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.0988" x2="10.9982" y2="3.0988" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.0988" x2="10.9982" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.3782" x2="9.9822" y2="3.3782" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.8862" x2="9.9822" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="3.6068" x2="10.9982" y2="3.6068" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.6068" x2="10.9982" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="3.8862" x2="9.9822" y2="3.8862" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.3942" x2="9.9822" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.1148" x2="10.9982" y2="4.1148" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.1148" x2="10.9982" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.3942" x2="9.9822" y2="4.3942" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.9022" x2="9.9822" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="4.6228" x2="10.9982" y2="4.6228" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.6228" x2="10.9982" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="4.9022" x2="9.9822" y2="4.9022" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.3848" x2="9.9822" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.1054" x2="10.9982" y2="5.1054" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.1054" x2="10.9982" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.3848" x2="9.9822" y2="5.3848" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.8928" x2="9.9822" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="5.6134" x2="10.9982" y2="5.6134" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.6134" x2="10.9982" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="5.8928" x2="9.9822" y2="5.8928" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.4008" x2="9.9822" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.1214" x2="10.9982" y2="6.1214" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.1214" x2="10.9982" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.4008" x2="9.9822" y2="6.4008" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.8834" x2="9.9822" y2="6.604" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="6.604" x2="10.9982" y2="6.604" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.604" x2="10.9982" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="6.8834" x2="9.9822" y2="6.8834" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.3914" x2="9.9822" y2="7.112" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.112" x2="10.9982" y2="7.112" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.112" x2="10.9982" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.3914" x2="9.9822" y2="7.3914" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.8994" x2="9.9822" y2="7.62" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="7.62" x2="10.9982" y2="7.62" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.62" x2="10.9982" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="7.8994" x2="9.9822" y2="7.8994" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.382" x2="9.9822" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.1026" x2="10.9982" y2="8.1026" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.1026" x2="10.9982" y2="8.382" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.382" x2="9.9822" y2="8.382" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.89" x2="9.9822" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="9.9822" y1="8.6106" x2="10.9982" y2="8.6106" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.6106" x2="10.9982" y2="8.89" width="0.1524" layer="51"/>
<wire x1="10.9982" y1="8.89" x2="9.9822" y2="8.89" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="8.7376" x2="-8.7376" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="-10.0076" x2="10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="-10.0076" x2="10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="10.0076" y1="10.0076" x2="-10.0076" y2="10.0076" width="0.1524" layer="51"/>
<wire x1="-10.0076" y1="10.0076" x2="-10.0076" y2="-10.0076" width="0.1524" layer="51"/>
<text x="-10.1854" y="8.3566" size="1.27" layer="51" ratio="6" rot="SR0">*</text>
<wire x1="-0.254" y1="0" x2="0.254" y2="0" width="0.1524" layer="23"/>
<wire x1="0" y1="-0.254" x2="0" y2="0.254" width="0.1524" layer="23"/>
<text x="-3.2766" y="-0.635" size="1.27" layer="25" ratio="6" rot="SR0">&gt;Name</text>
</package>
</packages>
<packages3d>
<package3d name="TSOP54-400" urn="urn:adsk.eagle:package:18739/1" type="box">
<description>54-Pin Plastic TSOP (400 mil)
Source: http://download.micron.com/pdf/datasheets/dram/sdram/256MSDRAM.pdf</description>
<packageinstances>
<packageinstance name="TSOP54-400"/>
</packageinstances>
</package3d>
</packages3d>
<symbols>
<symbol name="MT48LC64/32/16M-PWR">
<wire x1="-5.08" y1="22.86" x2="7.62" y2="22.86" width="0.254" layer="94"/>
<wire x1="7.62" y1="22.86" x2="7.62" y2="-22.86" width="0.254" layer="94"/>
<wire x1="7.62" y1="-22.86" x2="-5.08" y2="-22.86" width="0.254" layer="94"/>
<wire x1="-5.08" y1="-22.86" x2="-5.08" y2="22.86" width="0.254" layer="94"/>
<text x="-5.08" y="24.13" size="1.778" layer="95">&gt;NAME</text>
<text x="-5.08" y="-25.4" size="1.778" layer="96">&gt;VALUE</text>
<pin name="VDDQ@1" x="-7.62" y="10.16" length="short" direction="pwr"/>
<pin name="VDDQ@2" x="-7.62" y="7.62" length="short" direction="pwr"/>
<pin name="VDDQ@3" x="-7.62" y="5.08" length="short" direction="pwr"/>
<pin name="VDDQ@4" x="-7.62" y="2.54" length="short" direction="pwr"/>
<pin name="VSSQ@1" x="-7.62" y="-2.54" length="short" direction="pwr"/>
<pin name="VSSQ@2" x="-7.62" y="-5.08" length="short" direction="pwr"/>
<pin name="VSSQ@3" x="-7.62" y="-7.62" length="short" direction="pwr"/>
<pin name="VSSQ@4" x="-7.62" y="-10.16" length="short" direction="pwr"/>
<pin name="VDD@1" x="-7.62" y="20.32" length="short" direction="pwr"/>
<pin name="VDD@2" x="-7.62" y="17.78" length="short" direction="pwr"/>
<pin name="VDD@3" x="-7.62" y="15.24" length="short" direction="pwr"/>
<pin name="VSS@1" x="-7.62" y="-15.24" length="short" direction="pwr"/>
<pin name="VSS@2" x="-7.62" y="-17.78" length="short" direction="pwr"/>
<pin name="VSS@3" x="-7.62" y="-20.32" length="short" direction="pwr"/>
</symbol>
<symbol name="MT48LC64M444A2">
<wire x1="-10.16" y1="27.94" x2="12.7" y2="27.94" width="0.254" layer="94"/>
<wire x1="12.7" y1="27.94" x2="12.7" y2="-33.02" width="0.254" layer="94"/>
<wire x1="12.7" y1="-33.02" x2="-10.16" y2="-33.02" width="0.254" layer="94"/>
<wire x1="-10.16" y1="-33.02" x2="-10.16" y2="27.94" width="0.254" layer="94"/>
<text x="-10.16" y="29.21" size="1.778" layer="95">&gt;NAME</text>
<text x="-10.16" y="-35.56" size="1.778" layer="96">&gt;VALUE</text>
<pin name="CLK" x="-12.7" y="25.4" length="short" direction="in"/>
<pin name="CKE" x="-12.7" y="22.86" length="short" direction="in"/>
<pin name="\CS" x="-12.7" y="20.32" length="short" direction="in"/>
<pin name="!WE" x="15.24" y="-22.86" length="short" direction="in" rot="R180"/>
<pin name="!CAS" x="15.24" y="-27.94" length="short" direction="in" rot="R180"/>
<pin name="!RAS" x="15.24" y="-30.48" length="short" direction="in" rot="R180"/>
<pin name="DQML" x="-12.7" y="15.24" length="short" direction="in"/>
<pin name="DQMH" x="-12.7" y="12.7" length="short" direction="in"/>
<pin name="BA0" x="-12.7" y="7.62" length="short" direction="in"/>
<pin name="BA1" x="-12.7" y="5.08" length="short" direction="in"/>
<pin name="A0" x="-12.7" y="0" length="short" direction="in"/>
<pin name="A1" x="-12.7" y="-2.54" length="short" direction="in"/>
<pin name="A2" x="-12.7" y="-5.08" length="short" direction="in"/>
<pin name="A3" x="-12.7" y="-7.62" length="short" direction="in"/>
<pin name="A4" x="-12.7" y="-10.16" length="short" direction="in"/>
<pin name="A5" x="-12.7" y="-12.7" length="short" direction="in"/>
<pin name="A6" x="-12.7" y="-15.24" length="short" direction="in"/>
<pin name="A7" x="-12.7" y="-17.78" length="short" direction="in"/>
<pin name="A8" x="-12.7" y="-20.32" length="short" direction="in"/>
<pin name="A9" x="-12.7" y="-22.86" length="short" direction="in"/>
<pin name="A10" x="-12.7" y="-25.4" length="short" direction="in"/>
<pin name="A11" x="-12.7" y="-27.94" length="short" direction="in"/>
<pin name="A12" x="-12.7" y="-30.48" length="short" direction="in"/>
<pin name="DQ0" x="15.24" y="20.32" length="short" direction="hiz" rot="R180"/>
<pin name="DQ1" x="15.24" y="17.78" length="short" direction="hiz" rot="R180"/>
<pin name="DQ2" x="15.24" y="15.24" length="short" direction="hiz" rot="R180"/>
<pin name="DQ3" x="15.24" y="12.7" length="short" direction="hiz" rot="R180"/>
<pin name="DQ4" x="15.24" y="10.16" length="short" direction="hiz" rot="R180"/>
<pin name="DQ5" x="15.24" y="7.62" length="short" direction="hiz" rot="R180"/>
<pin name="DQ6" x="15.24" y="5.08" length="short" direction="hiz" rot="R180"/>
<pin name="DQ7" x="15.24" y="2.54" length="short" direction="hiz" rot="R180"/>
<pin name="DQ8" x="15.24" y="0" length="short" direction="hiz" rot="R180"/>
<pin name="DQ9" x="15.24" y="-2.54" length="short" direction="hiz" rot="R180"/>
<pin name="DQ10" x="15.24" y="-5.08" length="short" direction="hiz" rot="R180"/>
<pin name="DQ11" x="15.24" y="-7.62" length="short" direction="hiz" rot="R180"/>
<pin name="DQ12" x="15.24" y="-10.16" length="short" direction="hiz" rot="R180"/>
<pin name="DQ13" x="15.24" y="-12.7" length="short" direction="hiz" rot="R180"/>
<pin name="DQ14" x="15.24" y="-15.24" length="short" direction="hiz" rot="R180"/>
<pin name="DQ15" x="15.24" y="-17.78" length="short" direction="hiz" rot="R180"/>
<pin name="NC" x="15.24" y="25.4" length="short" direction="nc" rot="R180"/>
</symbol>
<symbol name="ICE40HX4K-TQ144">
<pin name="IOB_81_GBIN5" x="2.54" y="0" length="middle" direction="pas"/>
<pin name="IOB_82_GBIN4" x="2.54" y="-2.54" length="middle" direction="pas"/>
<pin name="IOL_13B_GBIN7" x="2.54" y="-7.62" length="middle" direction="pas"/>
<pin name="IOL_14A_GBIN6" x="2.54" y="-10.16" length="middle" direction="pas"/>
<pin name="IOR_140_GBIN3" x="2.54" y="-15.24" length="middle" direction="pas"/>
<pin name="IOR_141_GBIN2" x="2.54" y="-17.78" length="middle" direction="pas"/>
<pin name="IOT_197_GBIN1" x="2.54" y="-22.86" length="middle" direction="pas"/>
<pin name="CDONE" x="2.54" y="-27.94" length="middle" direction="pas"/>
<pin name="CRESET_B" x="2.54" y="-30.48" length="middle" direction="pas"/>
<pin name="IOL_2A" x="2.54" y="-35.56" length="middle" direction="pas"/>
<pin name="IOL_2B" x="2.54" y="-38.1" length="middle" direction="pas"/>
<pin name="IOL_3A" x="2.54" y="-40.64" length="middle" direction="pas"/>
<pin name="IOL_3B" x="2.54" y="-43.18" length="middle" direction="pas"/>
<pin name="IOL_4A" x="2.54" y="-45.72" length="middle" direction="pas"/>
<pin name="IOL_4B" x="2.54" y="-48.26" length="middle" direction="pas"/>
<pin name="IOL_5A" x="2.54" y="-50.8" length="middle" direction="pas"/>
<pin name="IOL_5B" x="2.54" y="-53.34" length="middle" direction="pas"/>
<pin name="IOL_8A" x="2.54" y="-55.88" length="middle" direction="pas"/>
<pin name="IOL_8B" x="2.54" y="-58.42" length="middle" direction="pas"/>
<pin name="IOL_10A" x="2.54" y="-60.96" length="middle" direction="pas"/>
<pin name="IOL_10B" x="2.54" y="-63.5" length="middle" direction="pas"/>
<pin name="IOL_12A" x="2.54" y="-66.04" length="middle" direction="pas"/>
<pin name="IOL_12B" x="2.54" y="-68.58" length="middle" direction="pas"/>
<pin name="IOL_13A" x="2.54" y="-71.12" length="middle" direction="pas"/>
<pin name="IOL_14B" x="2.54" y="-73.66" length="middle" direction="pas"/>
<pin name="IOL_17A" x="2.54" y="-76.2" length="middle" direction="pas"/>
<pin name="IOL_17B" x="2.54" y="-78.74" length="middle" direction="pas"/>
<pin name="IOL_18A" x="2.54" y="-81.28" length="middle" direction="pas"/>
<pin name="IOL_18B" x="2.54" y="-83.82" length="middle" direction="pas"/>
<pin name="IOL_23A" x="2.54" y="-86.36" length="middle" direction="pas"/>
<pin name="IOL_23B" x="2.54" y="-88.9" length="middle" direction="pas"/>
<pin name="IOL_24A" x="2.54" y="-91.44" length="middle" direction="pas"/>
<pin name="IOL_24B" x="2.54" y="-93.98" length="middle" direction="pas"/>
<pin name="IOL_25A" x="2.54" y="-96.52" length="middle" direction="pas"/>
<pin name="IOL_25B" x="2.54" y="-99.06" length="middle" direction="pas"/>
<pin name="IOB_56" x="78.74" y="0" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_57" x="78.74" y="-2.54" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_61" x="78.74" y="-5.08" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_63" x="78.74" y="-7.62" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_64" x="78.74" y="-10.16" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_71" x="78.74" y="-12.7" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_72" x="78.74" y="-15.24" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_73" x="78.74" y="-17.78" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_79" x="78.74" y="-20.32" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_80" x="78.74" y="-22.86" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_91" x="78.74" y="-25.4" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_94" x="78.74" y="-27.94" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_95" x="78.74" y="-30.48" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_96" x="78.74" y="-33.02" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_102" x="78.74" y="-35.56" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_103_CBSEL0" x="78.74" y="-38.1" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_104_CBSEL1" x="78.74" y="-40.64" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_105_SDO" x="78.74" y="-43.18" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_106_SDI" x="78.74" y="-45.72" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_107_SCK" x="78.74" y="-48.26" length="middle" direction="pas" rot="R180"/>
<pin name="IOB_108_SS" x="78.74" y="-50.8" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_109" x="78.74" y="-55.88" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_110" x="78.74" y="-58.42" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_111" x="78.74" y="-60.96" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_112" x="78.74" y="-63.5" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_114" x="78.74" y="-66.04" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_115" x="78.74" y="-68.58" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_116" x="78.74" y="-71.12" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_117" x="78.74" y="-73.66" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_118" x="78.74" y="-76.2" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_119" x="78.74" y="-78.74" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_120" x="78.74" y="-81.28" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_128" x="78.74" y="-83.82" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_136" x="78.74" y="-86.36" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_137" x="78.74" y="-88.9" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_138" x="78.74" y="-91.44" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_139" x="78.74" y="-93.98" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_144" x="78.74" y="-96.52" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_146" x="78.74" y="-99.06" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_147" x="78.74" y="-101.6" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_148" x="78.74" y="-104.14" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_152" x="78.74" y="-106.68" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_160" x="78.74" y="-109.22" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_161" x="78.74" y="-111.76" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_164" x="78.74" y="-114.3" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_165" x="78.74" y="-116.84" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_166" x="78.74" y="-119.38" length="middle" direction="pas" rot="R180"/>
<pin name="IOR_167" x="78.74" y="-121.92" length="middle" direction="pas" rot="R180"/>
<wire x1="7.62" y1="7.62" x2="7.62" y2="-127" width="0.1524" layer="94"/>
<wire x1="7.62" y1="-127" x2="73.66" y2="-127" width="0.1524" layer="94"/>
<wire x1="73.66" y1="-127" x2="73.66" y2="7.62" width="0.1524" layer="94"/>
<wire x1="73.66" y1="7.62" x2="7.62" y2="7.62" width="0.1524" layer="94"/>
<text x="35.2806" y="4.0386" size="2.0828" layer="97" ratio="6" rot="SR0">1 of 3</text>
<text x="35.9156" y="11.6586" size="2.0828" layer="95" ratio="6" rot="SR0">&gt;Name</text>
<text x="35.2806" y="9.1186" size="2.0828" layer="96" ratio="6" rot="SR0">&gt;Value</text>
</symbol>
<symbol name="ICE40HX4K-TQ144_A">
<pin name="IOT_168" x="2.54" y="0" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_169" x="2.54" y="-2.54" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_170" x="2.54" y="-5.08" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_171" x="2.54" y="-7.62" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_172" x="2.54" y="-10.16" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_173" x="2.54" y="-12.7" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_174" x="2.54" y="-15.24" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_177" x="2.54" y="-17.78" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_178" x="2.54" y="-20.32" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_179" x="2.54" y="-22.86" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_181" x="2.54" y="-25.4" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_190" x="2.54" y="-27.94" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_191" x="2.54" y="-30.48" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_192" x="2.54" y="-33.02" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_198_GBIN0" x="2.54" y="-35.56" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_206" x="2.54" y="-38.1" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_212" x="2.54" y="-40.64" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_213" x="2.54" y="-43.18" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_214" x="2.54" y="-45.72" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_215" x="2.54" y="-48.26" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_216" x="2.54" y="-50.8" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_217" x="2.54" y="-53.34" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_219" x="2.54" y="-55.88" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_220" x="2.54" y="-58.42" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_221" x="2.54" y="-60.96" length="middle" direction="pas" rot="R180"/>
<pin name="IOT_222" x="2.54" y="-63.5" length="middle" direction="pas" rot="R180"/>
<wire x1="-43.18" y1="5.08" x2="-43.18" y2="-68.58" width="0.1524" layer="94"/>
<wire x1="-43.18" y1="-68.58" x2="-7.62" y2="-68.58" width="0.1524" layer="94"/>
<wire x1="-7.62" y1="-68.58" x2="-7.62" y2="5.08" width="0.1524" layer="94"/>
<wire x1="-7.62" y1="5.08" x2="-43.18" y2="5.08" width="0.1524" layer="94"/>
<text x="-30.7594" y="1.4986" size="2.0828" layer="97" ratio="6" rot="SR0">2 of 3</text>
<text x="-30.1244" y="9.1186" size="2.0828" layer="95" ratio="6" rot="SR0">&gt;Name</text>
<text x="-30.7594" y="6.5786" size="2.0828" layer="96" ratio="6" rot="SR0">&gt;Value</text>
</symbol>
<symbol name="ICE40HX4K-TQ144_B">
<pin name="NC_2" x="2.54" y="0" length="middle" direction="nc"/>
<pin name="NC_3" x="2.54" y="-2.54" length="middle" direction="nc"/>
<pin name="NC_4" x="2.54" y="-5.08" length="middle" direction="nc"/>
<pin name="NC_5" x="2.54" y="-7.62" length="middle" direction="nc"/>
<pin name="NC_6" x="2.54" y="-10.16" length="middle" direction="nc"/>
<pin name="NC_7" x="2.54" y="-12.7" length="middle" direction="pas"/>
<pin name="NC" x="2.54" y="-15.24" length="middle" direction="nc"/>
<pin name="VCC_2" x="2.54" y="-20.32" length="middle" direction="pwr"/>
<pin name="VCC_3" x="2.54" y="-22.86" length="middle" direction="pwr"/>
<pin name="VCC_4" x="2.54" y="-25.4" length="middle" direction="pwr"/>
<pin name="VCC" x="2.54" y="-27.94" length="middle" direction="pwr"/>
<pin name="VCC_SPI" x="2.54" y="-30.48" length="middle" direction="pwr"/>
<pin name="VCCIO_0_2" x="2.54" y="-33.02" length="middle" direction="pwr"/>
<pin name="VCCIO_0" x="2.54" y="-35.56" length="middle" direction="pwr"/>
<pin name="VCCIO_1_2" x="2.54" y="-38.1" length="middle" direction="pwr"/>
<pin name="VCCIO_1" x="2.54" y="-40.64" length="middle" direction="pwr"/>
<pin name="VCCIO_2_2" x="2.54" y="-43.18" length="middle" direction="pwr"/>
<pin name="VCCIO_2" x="2.54" y="-45.72" length="middle" direction="pwr"/>
<pin name="VCCIO_3_2" x="2.54" y="-48.26" length="middle" direction="pwr"/>
<pin name="VCCIO_3" x="2.54" y="-50.8" length="middle" direction="pwr"/>
<pin name="VCCPLL0" x="2.54" y="-53.34" length="middle" direction="pwr"/>
<pin name="VCCPLL1" x="2.54" y="-55.88" length="middle" direction="pwr"/>
<pin name="VPP_2V5" x="2.54" y="-60.96" length="middle" direction="pwr"/>
<pin name="VPP_FAST" x="2.54" y="-63.5" length="middle" direction="pwr"/>
<pin name="GND_2" x="53.34" y="-2.54" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_3" x="53.34" y="-5.08" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_4" x="53.34" y="-7.62" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_5" x="53.34" y="-10.16" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_6" x="53.34" y="-12.7" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_7" x="53.34" y="-15.24" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_8" x="53.34" y="-17.78" length="middle" direction="pwr" rot="R180"/>
<pin name="GND_9" x="53.34" y="-20.32" length="middle" direction="pwr" rot="R180"/>
<pin name="GND" x="53.34" y="-22.86" length="middle" direction="pwr" rot="R180"/>
<pin name="GNDPLL0" x="53.34" y="-25.4" length="middle" direction="pwr" rot="R180"/>
<pin name="GNDPLL1" x="53.34" y="-27.94" length="middle" direction="pwr" rot="R180"/>
<wire x1="7.62" y1="5.08" x2="7.62" y2="-68.58" width="0.1524" layer="94"/>
<wire x1="7.62" y1="-68.58" x2="48.26" y2="-68.58" width="0.1524" layer="94"/>
<wire x1="48.26" y1="-68.58" x2="48.26" y2="5.08" width="0.1524" layer="94"/>
<wire x1="48.26" y1="5.08" x2="7.62" y2="5.08" width="0.1524" layer="94"/>
<text x="22.5806" y="1.4986" size="2.0828" layer="97" ratio="6" rot="SR0">3 of 3</text>
<text x="23.2156" y="9.1186" size="2.0828" layer="95" ratio="6" rot="SR0">&gt;Name</text>
<text x="22.5806" y="6.5786" size="2.0828" layer="96" ratio="6" rot="SR0">&gt;Value</text>
</symbol>
</symbols>
<devicesets>
<deviceset name="MT48LC16M16A2" prefix="IC">
<description>&lt;b&gt;256Mb: x16 SDRAM&lt;/b&gt; MT48LC16M16A2 - 4 Meg x 16 x 4 banks&lt;p&gt;
Source: http://download.micron.com/pdf/datasheets/dram/sdram/256MSDRAM.pdf</description>
<gates>
<gate name="P" symbol="MT48LC64/32/16M-PWR" x="35.56" y="0" addlevel="request"/>
<gate name="G$1" symbol="MT48LC64M444A2" x="0" y="0"/>
</gates>
<devices>
<device name="" package="TSOP54-400">
<connects>
<connect gate="G$1" pin="!CAS" pad="17"/>
<connect gate="G$1" pin="!RAS" pad="18"/>
<connect gate="G$1" pin="!WE" pad="16"/>
<connect gate="G$1" pin="A0" pad="23"/>
<connect gate="G$1" pin="A1" pad="24"/>
<connect gate="G$1" pin="A10" pad="22"/>
<connect gate="G$1" pin="A11" pad="35"/>
<connect gate="G$1" pin="A12" pad="36"/>
<connect gate="G$1" pin="A2" pad="25"/>
<connect gate="G$1" pin="A3" pad="26"/>
<connect gate="G$1" pin="A4" pad="29"/>
<connect gate="G$1" pin="A5" pad="30"/>
<connect gate="G$1" pin="A6" pad="31"/>
<connect gate="G$1" pin="A7" pad="32"/>
<connect gate="G$1" pin="A8" pad="33"/>
<connect gate="G$1" pin="A9" pad="34"/>
<connect gate="G$1" pin="BA0" pad="20"/>
<connect gate="G$1" pin="BA1" pad="21"/>
<connect gate="G$1" pin="CKE" pad="37"/>
<connect gate="G$1" pin="CLK" pad="38"/>
<connect gate="G$1" pin="DQ0" pad="2"/>
<connect gate="G$1" pin="DQ1" pad="4"/>
<connect gate="G$1" pin="DQ10" pad="45"/>
<connect gate="G$1" pin="DQ11" pad="47"/>
<connect gate="G$1" pin="DQ12" pad="48"/>
<connect gate="G$1" pin="DQ13" pad="50"/>
<connect gate="G$1" pin="DQ14" pad="51"/>
<connect gate="G$1" pin="DQ15" pad="53"/>
<connect gate="G$1" pin="DQ2" pad="5"/>
<connect gate="G$1" pin="DQ3" pad="7"/>
<connect gate="G$1" pin="DQ4" pad="8"/>
<connect gate="G$1" pin="DQ5" pad="10"/>
<connect gate="G$1" pin="DQ6" pad="11"/>
<connect gate="G$1" pin="DQ7" pad="13"/>
<connect gate="G$1" pin="DQ8" pad="42"/>
<connect gate="G$1" pin="DQ9" pad="44"/>
<connect gate="G$1" pin="DQMH" pad="39"/>
<connect gate="G$1" pin="DQML" pad="15"/>
<connect gate="G$1" pin="NC" pad="40"/>
<connect gate="G$1" pin="\CS" pad="19"/>
<connect gate="P" pin="VDD@1" pad="1"/>
<connect gate="P" pin="VDD@2" pad="14"/>
<connect gate="P" pin="VDD@3" pad="27"/>
<connect gate="P" pin="VDDQ@1" pad="3"/>
<connect gate="P" pin="VDDQ@2" pad="9"/>
<connect gate="P" pin="VDDQ@3" pad="43"/>
<connect gate="P" pin="VDDQ@4" pad="49"/>
<connect gate="P" pin="VSS@1" pad="28"/>
<connect gate="P" pin="VSS@2" pad="41"/>
<connect gate="P" pin="VSS@3" pad="54"/>
<connect gate="P" pin="VSSQ@1" pad="6"/>
<connect gate="P" pin="VSSQ@2" pad="12"/>
<connect gate="P" pin="VSSQ@3" pad="46"/>
<connect gate="P" pin="VSSQ@4" pad="52"/>
</connects>
<package3dinstances>
<package3dinstance package3d_urn="urn:adsk.eagle:package:18739/1"/>
</package3dinstances>
<technologies>
<technology name="">
<attribute name="MF" value="" constant="no"/>
<attribute name="MPN" value="" constant="no"/>
<attribute name="OC_FARNELL" value="unknown" constant="no"/>
<attribute name="OC_NEWARK" value="unknown" constant="no"/>
</technology>
</technologies>
</device>
</devices>
</deviceset>
<deviceset name="ICE40HX4K-TQ144" prefix="U">
<gates>
<gate name="A" symbol="ICE40HX4K-TQ144" x="0" y="0"/>
<gate name="B" symbol="ICE40HX4K-TQ144_A" x="94.996" y="0"/>
<gate name="C" symbol="ICE40HX4K-TQ144_B" x="150.1648" y="0"/>
</gates>
<devices>
<device name="" package="TQFP144">
<connects>
<connect gate="A" pin="CDONE" pad="65"/>
<connect gate="A" pin="CRESET_B" pad="66"/>
<connect gate="A" pin="IOB_102" pad="62"/>
<connect gate="A" pin="IOB_103_CBSEL0" pad="63"/>
<connect gate="A" pin="IOB_104_CBSEL1" pad="64"/>
<connect gate="A" pin="IOB_105_SDO" pad="67"/>
<connect gate="A" pin="IOB_106_SDI" pad="68"/>
<connect gate="A" pin="IOB_107_SCK" pad="70"/>
<connect gate="A" pin="IOB_108_SS" pad="71"/>
<connect gate="A" pin="IOB_56" pad="37"/>
<connect gate="A" pin="IOB_57" pad="38"/>
<connect gate="A" pin="IOB_61" pad="39"/>
<connect gate="A" pin="IOB_63" pad="41"/>
<connect gate="A" pin="IOB_64" pad="42"/>
<connect gate="A" pin="IOB_71" pad="43"/>
<connect gate="A" pin="IOB_72" pad="44"/>
<connect gate="A" pin="IOB_73" pad="45"/>
<connect gate="A" pin="IOB_79" pad="47"/>
<connect gate="A" pin="IOB_80" pad="48"/>
<connect gate="A" pin="IOB_81_GBIN5" pad="49"/>
<connect gate="A" pin="IOB_82_GBIN4" pad="52"/>
<connect gate="A" pin="IOB_91" pad="55"/>
<connect gate="A" pin="IOB_94" pad="56"/>
<connect gate="A" pin="IOB_95" pad="60"/>
<connect gate="A" pin="IOB_96" pad="61"/>
<connect gate="A" pin="IOL_10A" pad="15"/>
<connect gate="A" pin="IOL_10B" pad="16"/>
<connect gate="A" pin="IOL_12A" pad="17"/>
<connect gate="A" pin="IOL_12B" pad="18"/>
<connect gate="A" pin="IOL_13A" pad="19"/>
<connect gate="A" pin="IOL_13B_GBIN7" pad="20"/>
<connect gate="A" pin="IOL_14A_GBIN6" pad="21"/>
<connect gate="A" pin="IOL_14B" pad="22"/>
<connect gate="A" pin="IOL_17A" pad="23"/>
<connect gate="A" pin="IOL_17B" pad="24"/>
<connect gate="A" pin="IOL_18A" pad="25"/>
<connect gate="A" pin="IOL_18B" pad="26"/>
<connect gate="A" pin="IOL_23A" pad="28"/>
<connect gate="A" pin="IOL_23B" pad="29"/>
<connect gate="A" pin="IOL_24A" pad="31"/>
<connect gate="A" pin="IOL_24B" pad="32"/>
<connect gate="A" pin="IOL_25A" pad="33"/>
<connect gate="A" pin="IOL_25B" pad="34"/>
<connect gate="A" pin="IOL_2A" pad="1"/>
<connect gate="A" pin="IOL_2B" pad="2"/>
<connect gate="A" pin="IOL_3A" pad="3"/>
<connect gate="A" pin="IOL_3B" pad="4"/>
<connect gate="A" pin="IOL_4A" pad="7"/>
<connect gate="A" pin="IOL_4B" pad="8"/>
<connect gate="A" pin="IOL_5A" pad="9"/>
<connect gate="A" pin="IOL_5B" pad="10"/>
<connect gate="A" pin="IOL_8A" pad="11"/>
<connect gate="A" pin="IOL_8B" pad="12"/>
<connect gate="A" pin="IOR_109" pad="73"/>
<connect gate="A" pin="IOR_110" pad="74"/>
<connect gate="A" pin="IOR_111" pad="75"/>
<connect gate="A" pin="IOR_112" pad="76"/>
<connect gate="A" pin="IOR_114" pad="78"/>
<connect gate="A" pin="IOR_115" pad="79"/>
<connect gate="A" pin="IOR_116" pad="80"/>
<connect gate="A" pin="IOR_117" pad="81"/>
<connect gate="A" pin="IOR_118" pad="82"/>
<connect gate="A" pin="IOR_119" pad="83"/>
<connect gate="A" pin="IOR_120" pad="84"/>
<connect gate="A" pin="IOR_128" pad="85"/>
<connect gate="A" pin="IOR_136" pad="87"/>
<connect gate="A" pin="IOR_137" pad="88"/>
<connect gate="A" pin="IOR_138" pad="90"/>
<connect gate="A" pin="IOR_139" pad="91"/>
<connect gate="A" pin="IOR_140_GBIN3" pad="93"/>
<connect gate="A" pin="IOR_141_GBIN2" pad="94"/>
<connect gate="A" pin="IOR_144" pad="95"/>
<connect gate="A" pin="IOR_146" pad="96"/>
<connect gate="A" pin="IOR_147" pad="97"/>
<connect gate="A" pin="IOR_148" pad="98"/>
<connect gate="A" pin="IOR_152" pad="99"/>
<connect gate="A" pin="IOR_160" pad="101"/>
<connect gate="A" pin="IOR_161" pad="102"/>
<connect gate="A" pin="IOR_164" pad="104"/>
<connect gate="A" pin="IOR_165" pad="105"/>
<connect gate="A" pin="IOR_166" pad="106"/>
<connect gate="A" pin="IOR_167" pad="107"/>
<connect gate="A" pin="IOT_197_GBIN1" pad="128"/>
<connect gate="B" pin="IOT_168" pad="110"/>
<connect gate="B" pin="IOT_169" pad="112"/>
<connect gate="B" pin="IOT_170" pad="113"/>
<connect gate="B" pin="IOT_171" pad="114"/>
<connect gate="B" pin="IOT_172" pad="115"/>
<connect gate="B" pin="IOT_173" pad="116"/>
<connect gate="B" pin="IOT_174" pad="117"/>
<connect gate="B" pin="IOT_177" pad="118"/>
<connect gate="B" pin="IOT_178" pad="119"/>
<connect gate="B" pin="IOT_179" pad="120"/>
<connect gate="B" pin="IOT_181" pad="121"/>
<connect gate="B" pin="IOT_190" pad="122"/>
<connect gate="B" pin="IOT_191" pad="124"/>
<connect gate="B" pin="IOT_192" pad="125"/>
<connect gate="B" pin="IOT_198_GBIN0" pad="129"/>
<connect gate="B" pin="IOT_206" pad="130"/>
<connect gate="B" pin="IOT_212" pad="134"/>
<connect gate="B" pin="IOT_213" pad="135"/>
<connect gate="B" pin="IOT_214" pad="136"/>
<connect gate="B" pin="IOT_215" pad="137"/>
<connect gate="B" pin="IOT_216" pad="138"/>
<connect gate="B" pin="IOT_217" pad="139"/>
<connect gate="B" pin="IOT_219" pad="141"/>
<connect gate="B" pin="IOT_220" pad="142"/>
<connect gate="B" pin="IOT_221" pad="143"/>
<connect gate="B" pin="IOT_222" pad="144"/>
<connect gate="C" pin="GND" pad="140"/>
<connect gate="C" pin="GNDPLL0" pad="53"/>
<connect gate="C" pin="GNDPLL1" pad="127"/>
<connect gate="C" pin="GND_2" pad="5"/>
<connect gate="C" pin="GND_3" pad="13"/>
<connect gate="C" pin="GND_4" pad="14"/>
<connect gate="C" pin="GND_5" pad="59"/>
<connect gate="C" pin="GND_6" pad="69"/>
<connect gate="C" pin="GND_7" pad="86"/>
<connect gate="C" pin="GND_8" pad="103"/>
<connect gate="C" pin="GND_9" pad="132"/>
<connect gate="C" pin="NC" pad="133"/>
<connect gate="C" pin="NC_2" pad="35"/>
<connect gate="C" pin="NC_3" pad="36"/>
<connect gate="C" pin="NC_4" pad="50"/>
<connect gate="C" pin="NC_5" pad="51"/>
<connect gate="C" pin="NC_6" pad="58"/>
<connect gate="C" pin="NC_7" pad="77"/>
<connect gate="C" pin="VCC" pad="111"/>
<connect gate="C" pin="VCCIO_0" pad="131"/>
<connect gate="C" pin="VCCIO_0_2" pad="123"/>
<connect gate="C" pin="VCCIO_1" pad="100"/>
<connect gate="C" pin="VCCIO_1_2" pad="89"/>
<connect gate="C" pin="VCCIO_2" pad="57"/>
<connect gate="C" pin="VCCIO_2_2" pad="46"/>
<connect gate="C" pin="VCCIO_3" pad="30"/>
<connect gate="C" pin="VCCIO_3_2" pad="6"/>
<connect gate="C" pin="VCCPLL0" pad="54"/>
<connect gate="C" pin="VCCPLL1" pad="126"/>
<connect gate="C" pin="VCC_2" pad="27"/>
<connect gate="C" pin="VCC_3" pad="40"/>
<connect gate="C" pin="VCC_4" pad="92"/>
<connect gate="C" pin="VCC_SPI" pad="72"/>
<connect gate="C" pin="VPP_2V5" pad="108"/>
<connect gate="C" pin="VPP_FAST" pad="109"/>
</connects>
<technologies>
<technology name="">
<attribute name="MANUFACTURER_PART_NUMBER" value="ICE40HX4KTQ144" constant="no"/>
<attribute name="VENDOR" value="Lattice" constant="no"/>
</technology>
</technologies>
</device>
<device name="TQFP144-M" package="TQFP144-M">
<connects>
<connect gate="A" pin="CDONE" pad="65"/>
<connect gate="A" pin="CRESET_B" pad="66"/>
<connect gate="A" pin="IOB_102" pad="62"/>
<connect gate="A" pin="IOB_103_CBSEL0" pad="63"/>
<connect gate="A" pin="IOB_104_CBSEL1" pad="64"/>
<connect gate="A" pin="IOB_105_SDO" pad="67"/>
<connect gate="A" pin="IOB_106_SDI" pad="68"/>
<connect gate="A" pin="IOB_107_SCK" pad="70"/>
<connect gate="A" pin="IOB_108_SS" pad="71"/>
<connect gate="A" pin="IOB_56" pad="37"/>
<connect gate="A" pin="IOB_57" pad="38"/>
<connect gate="A" pin="IOB_61" pad="39"/>
<connect gate="A" pin="IOB_63" pad="41"/>
<connect gate="A" pin="IOB_64" pad="42"/>
<connect gate="A" pin="IOB_71" pad="43"/>
<connect gate="A" pin="IOB_72" pad="44"/>
<connect gate="A" pin="IOB_73" pad="45"/>
<connect gate="A" pin="IOB_79" pad="47"/>
<connect gate="A" pin="IOB_80" pad="48"/>
<connect gate="A" pin="IOB_81_GBIN5" pad="49"/>
<connect gate="A" pin="IOB_82_GBIN4" pad="52"/>
<connect gate="A" pin="IOB_91" pad="55"/>
<connect gate="A" pin="IOB_94" pad="56"/>
<connect gate="A" pin="IOB_95" pad="60"/>
<connect gate="A" pin="IOB_96" pad="61"/>
<connect gate="A" pin="IOL_10A" pad="15"/>
<connect gate="A" pin="IOL_10B" pad="16"/>
<connect gate="A" pin="IOL_12A" pad="17"/>
<connect gate="A" pin="IOL_12B" pad="18"/>
<connect gate="A" pin="IOL_13A" pad="19"/>
<connect gate="A" pin="IOL_13B_GBIN7" pad="20"/>
<connect gate="A" pin="IOL_14A_GBIN6" pad="21"/>
<connect gate="A" pin="IOL_14B" pad="22"/>
<connect gate="A" pin="IOL_17A" pad="23"/>
<connect gate="A" pin="IOL_17B" pad="24"/>
<connect gate="A" pin="IOL_18A" pad="25"/>
<connect gate="A" pin="IOL_18B" pad="26"/>
<connect gate="A" pin="IOL_23A" pad="28"/>
<connect gate="A" pin="IOL_23B" pad="29"/>
<connect gate="A" pin="IOL_24A" pad="31"/>
<connect gate="A" pin="IOL_24B" pad="32"/>
<connect gate="A" pin="IOL_25A" pad="33"/>
<connect gate="A" pin="IOL_25B" pad="34"/>
<connect gate="A" pin="IOL_2A" pad="1"/>
<connect gate="A" pin="IOL_2B" pad="2"/>
<connect gate="A" pin="IOL_3A" pad="3"/>
<connect gate="A" pin="IOL_3B" pad="4"/>
<connect gate="A" pin="IOL_4A" pad="7"/>
<connect gate="A" pin="IOL_4B" pad="8"/>
<connect gate="A" pin="IOL_5A" pad="9"/>
<connect gate="A" pin="IOL_5B" pad="10"/>
<connect gate="A" pin="IOL_8A" pad="11"/>
<connect gate="A" pin="IOL_8B" pad="12"/>
<connect gate="A" pin="IOR_109" pad="73"/>
<connect gate="A" pin="IOR_110" pad="74"/>
<connect gate="A" pin="IOR_111" pad="75"/>
<connect gate="A" pin="IOR_112" pad="76"/>
<connect gate="A" pin="IOR_114" pad="78"/>
<connect gate="A" pin="IOR_115" pad="79"/>
<connect gate="A" pin="IOR_116" pad="80"/>
<connect gate="A" pin="IOR_117" pad="81"/>
<connect gate="A" pin="IOR_118" pad="82"/>
<connect gate="A" pin="IOR_119" pad="83"/>
<connect gate="A" pin="IOR_120" pad="84"/>
<connect gate="A" pin="IOR_128" pad="85"/>
<connect gate="A" pin="IOR_136" pad="87"/>
<connect gate="A" pin="IOR_137" pad="88"/>
<connect gate="A" pin="IOR_138" pad="90"/>
<connect gate="A" pin="IOR_139" pad="91"/>
<connect gate="A" pin="IOR_140_GBIN3" pad="93"/>
<connect gate="A" pin="IOR_141_GBIN2" pad="94"/>
<connect gate="A" pin="IOR_144" pad="95"/>
<connect gate="A" pin="IOR_146" pad="96"/>
<connect gate="A" pin="IOR_147" pad="97"/>
<connect gate="A" pin="IOR_148" pad="98"/>
<connect gate="A" pin="IOR_152" pad="99"/>
<connect gate="A" pin="IOR_160" pad="101"/>
<connect gate="A" pin="IOR_161" pad="102"/>
<connect gate="A" pin="IOR_164" pad="104"/>
<connect gate="A" pin="IOR_165" pad="105"/>
<connect gate="A" pin="IOR_166" pad="106"/>
<connect gate="A" pin="IOR_167" pad="107"/>
<connect gate="A" pin="IOT_197_GBIN1" pad="128"/>
<connect gate="B" pin="IOT_168" pad="110"/>
<connect gate="B" pin="IOT_169" pad="112"/>
<connect gate="B" pin="IOT_170" pad="113"/>
<connect gate="B" pin="IOT_171" pad="114"/>
<connect gate="B" pin="IOT_172" pad="115"/>
<connect gate="B" pin="IOT_173" pad="116"/>
<connect gate="B" pin="IOT_174" pad="117"/>
<connect gate="B" pin="IOT_177" pad="118"/>
<connect gate="B" pin="IOT_178" pad="119"/>
<connect gate="B" pin="IOT_179" pad="120"/>
<connect gate="B" pin="IOT_181" pad="121"/>
<connect gate="B" pin="IOT_190" pad="122"/>
<connect gate="B" pin="IOT_191" pad="124"/>
<connect gate="B" pin="IOT_192" pad="125"/>
<connect gate="B" pin="IOT_198_GBIN0" pad="129"/>
<connect gate="B" pin="IOT_206" pad="130"/>
<connect gate="B" pin="IOT_212" pad="134"/>
<connect gate="B" pin="IOT_213" pad="135"/>
<connect gate="B" pin="IOT_214" pad="136"/>
<connect gate="B" pin="IOT_215" pad="137"/>
<connect gate="B" pin="IOT_216" pad="138"/>
<connect gate="B" pin="IOT_217" pad="139"/>
<connect gate="B" pin="IOT_219" pad="141"/>
<connect gate="B" pin="IOT_220" pad="142"/>
<connect gate="B" pin="IOT_221" pad="143"/>
<connect gate="B" pin="IOT_222" pad="144"/>
<connect gate="C" pin="GND" pad="140"/>
<connect gate="C" pin="GNDPLL0" pad="53"/>
<connect gate="C" pin="GNDPLL1" pad="127"/>
<connect gate="C" pin="GND_2" pad="5"/>
<connect gate="C" pin="GND_3" pad="13"/>
<connect gate="C" pin="GND_4" pad="14"/>
<connect gate="C" pin="GND_5" pad="59"/>
<connect gate="C" pin="GND_6" pad="69"/>
<connect gate="C" pin="GND_7" pad="86"/>
<connect gate="C" pin="GND_8" pad="103"/>
<connect gate="C" pin="GND_9" pad="132"/>
<connect gate="C" pin="NC" pad="133"/>
<connect gate="C" pin="NC_2" pad="35"/>
<connect gate="C" pin="NC_3" pad="36"/>
<connect gate="C" pin="NC_4" pad="50"/>
<connect gate="C" pin="NC_5" pad="51"/>
<connect gate="C" pin="NC_6" pad="58"/>
<connect gate="C" pin="NC_7" pad="77"/>
<connect gate="C" pin="VCC" pad="111"/>
<connect gate="C" pin="VCCIO_0" pad="131"/>
<connect gate="C" pin="VCCIO_0_2" pad="123"/>
<connect gate="C" pin="VCCIO_1" pad="100"/>
<connect gate="C" pin="VCCIO_1_2" pad="89"/>
<connect gate="C" pin="VCCIO_2" pad="57"/>
<connect gate="C" pin="VCCIO_2_2" pad="46"/>
<connect gate="C" pin="VCCIO_3" pad="30"/>
<connect gate="C" pin="VCCIO_3_2" pad="6"/>
<connect gate="C" pin="VCCPLL0" pad="54"/>
<connect gate="C" pin="VCCPLL1" pad="126"/>
<connect gate="C" pin="VCC_2" pad="27"/>
<connect gate="C" pin="VCC_3" pad="40"/>
<connect gate="C" pin="VCC_4" pad="92"/>
<connect gate="C" pin="VCC_SPI" pad="72"/>
<connect gate="C" pin="VPP_2V5" pad="108"/>
<connect gate="C" pin="VPP_FAST" pad="109"/>
</connects>
<technologies>
<technology name="">
<attribute name="MANUFACTURER_PART_NUMBER" value="ICE40HX4KTQ144" constant="no"/>
<attribute name="VENDOR" value="Lattice" constant="no"/>
</technology>
</technologies>
</device>
<device name="TQFP144-L" package="TQFP144-L">
<connects>
<connect gate="A" pin="CDONE" pad="65"/>
<connect gate="A" pin="CRESET_B" pad="66"/>
<connect gate="A" pin="IOB_102" pad="62"/>
<connect gate="A" pin="IOB_103_CBSEL0" pad="63"/>
<connect gate="A" pin="IOB_104_CBSEL1" pad="64"/>
<connect gate="A" pin="IOB_105_SDO" pad="67"/>
<connect gate="A" pin="IOB_106_SDI" pad="68"/>
<connect gate="A" pin="IOB_107_SCK" pad="70"/>
<connect gate="A" pin="IOB_108_SS" pad="71"/>
<connect gate="A" pin="IOB_56" pad="37"/>
<connect gate="A" pin="IOB_57" pad="38"/>
<connect gate="A" pin="IOB_61" pad="39"/>
<connect gate="A" pin="IOB_63" pad="41"/>
<connect gate="A" pin="IOB_64" pad="42"/>
<connect gate="A" pin="IOB_71" pad="43"/>
<connect gate="A" pin="IOB_72" pad="44"/>
<connect gate="A" pin="IOB_73" pad="45"/>
<connect gate="A" pin="IOB_79" pad="47"/>
<connect gate="A" pin="IOB_80" pad="48"/>
<connect gate="A" pin="IOB_81_GBIN5" pad="49"/>
<connect gate="A" pin="IOB_82_GBIN4" pad="52"/>
<connect gate="A" pin="IOB_91" pad="55"/>
<connect gate="A" pin="IOB_94" pad="56"/>
<connect gate="A" pin="IOB_95" pad="60"/>
<connect gate="A" pin="IOB_96" pad="61"/>
<connect gate="A" pin="IOL_10A" pad="15"/>
<connect gate="A" pin="IOL_10B" pad="16"/>
<connect gate="A" pin="IOL_12A" pad="17"/>
<connect gate="A" pin="IOL_12B" pad="18"/>
<connect gate="A" pin="IOL_13A" pad="19"/>
<connect gate="A" pin="IOL_13B_GBIN7" pad="20"/>
<connect gate="A" pin="IOL_14A_GBIN6" pad="21"/>
<connect gate="A" pin="IOL_14B" pad="22"/>
<connect gate="A" pin="IOL_17A" pad="23"/>
<connect gate="A" pin="IOL_17B" pad="24"/>
<connect gate="A" pin="IOL_18A" pad="25"/>
<connect gate="A" pin="IOL_18B" pad="26"/>
<connect gate="A" pin="IOL_23A" pad="28"/>
<connect gate="A" pin="IOL_23B" pad="29"/>
<connect gate="A" pin="IOL_24A" pad="31"/>
<connect gate="A" pin="IOL_24B" pad="32"/>
<connect gate="A" pin="IOL_25A" pad="33"/>
<connect gate="A" pin="IOL_25B" pad="34"/>
<connect gate="A" pin="IOL_2A" pad="1"/>
<connect gate="A" pin="IOL_2B" pad="2"/>
<connect gate="A" pin="IOL_3A" pad="3"/>
<connect gate="A" pin="IOL_3B" pad="4"/>
<connect gate="A" pin="IOL_4A" pad="7"/>
<connect gate="A" pin="IOL_4B" pad="8"/>
<connect gate="A" pin="IOL_5A" pad="9"/>
<connect gate="A" pin="IOL_5B" pad="10"/>
<connect gate="A" pin="IOL_8A" pad="11"/>
<connect gate="A" pin="IOL_8B" pad="12"/>
<connect gate="A" pin="IOR_109" pad="73"/>
<connect gate="A" pin="IOR_110" pad="74"/>
<connect gate="A" pin="IOR_111" pad="75"/>
<connect gate="A" pin="IOR_112" pad="76"/>
<connect gate="A" pin="IOR_114" pad="78"/>
<connect gate="A" pin="IOR_115" pad="79"/>
<connect gate="A" pin="IOR_116" pad="80"/>
<connect gate="A" pin="IOR_117" pad="81"/>
<connect gate="A" pin="IOR_118" pad="82"/>
<connect gate="A" pin="IOR_119" pad="83"/>
<connect gate="A" pin="IOR_120" pad="84"/>
<connect gate="A" pin="IOR_128" pad="85"/>
<connect gate="A" pin="IOR_136" pad="87"/>
<connect gate="A" pin="IOR_137" pad="88"/>
<connect gate="A" pin="IOR_138" pad="90"/>
<connect gate="A" pin="IOR_139" pad="91"/>
<connect gate="A" pin="IOR_140_GBIN3" pad="93"/>
<connect gate="A" pin="IOR_141_GBIN2" pad="94"/>
<connect gate="A" pin="IOR_144" pad="95"/>
<connect gate="A" pin="IOR_146" pad="96"/>
<connect gate="A" pin="IOR_147" pad="97"/>
<connect gate="A" pin="IOR_148" pad="98"/>
<connect gate="A" pin="IOR_152" pad="99"/>
<connect gate="A" pin="IOR_160" pad="101"/>
<connect gate="A" pin="IOR_161" pad="102"/>
<connect gate="A" pin="IOR_164" pad="104"/>
<connect gate="A" pin="IOR_165" pad="105"/>
<connect gate="A" pin="IOR_166" pad="106"/>
<connect gate="A" pin="IOR_167" pad="107"/>
<connect gate="A" pin="IOT_197_GBIN1" pad="128"/>
<connect gate="B" pin="IOT_168" pad="110"/>
<connect gate="B" pin="IOT_169" pad="112"/>
<connect gate="B" pin="IOT_170" pad="113"/>
<connect gate="B" pin="IOT_171" pad="114"/>
<connect gate="B" pin="IOT_172" pad="115"/>
<connect gate="B" pin="IOT_173" pad="116"/>
<connect gate="B" pin="IOT_174" pad="117"/>
<connect gate="B" pin="IOT_177" pad="118"/>
<connect gate="B" pin="IOT_178" pad="119"/>
<connect gate="B" pin="IOT_179" pad="120"/>
<connect gate="B" pin="IOT_181" pad="121"/>
<connect gate="B" pin="IOT_190" pad="122"/>
<connect gate="B" pin="IOT_191" pad="124"/>
<connect gate="B" pin="IOT_192" pad="125"/>
<connect gate="B" pin="IOT_198_GBIN0" pad="129"/>
<connect gate="B" pin="IOT_206" pad="130"/>
<connect gate="B" pin="IOT_212" pad="134"/>
<connect gate="B" pin="IOT_213" pad="135"/>
<connect gate="B" pin="IOT_214" pad="136"/>
<connect gate="B" pin="IOT_215" pad="137"/>
<connect gate="B" pin="IOT_216" pad="138"/>
<connect gate="B" pin="IOT_217" pad="139"/>
<connect gate="B" pin="IOT_219" pad="141"/>
<connect gate="B" pin="IOT_220" pad="142"/>
<connect gate="B" pin="IOT_221" pad="143"/>
<connect gate="B" pin="IOT_222" pad="144"/>
<connect gate="C" pin="GND" pad="140"/>
<connect gate="C" pin="GNDPLL0" pad="53"/>
<connect gate="C" pin="GNDPLL1" pad="127"/>
<connect gate="C" pin="GND_2" pad="5"/>
<connect gate="C" pin="GND_3" pad="13"/>
<connect gate="C" pin="GND_4" pad="14"/>
<connect gate="C" pin="GND_5" pad="59"/>
<connect gate="C" pin="GND_6" pad="69"/>
<connect gate="C" pin="GND_7" pad="86"/>
<connect gate="C" pin="GND_8" pad="103"/>
<connect gate="C" pin="GND_9" pad="132"/>
<connect gate="C" pin="NC" pad="133"/>
<connect gate="C" pin="NC_2" pad="35"/>
<connect gate="C" pin="NC_3" pad="36"/>
<connect gate="C" pin="NC_4" pad="50"/>
<connect gate="C" pin="NC_5" pad="51"/>
<connect gate="C" pin="NC_6" pad="58"/>
<connect gate="C" pin="NC_7" pad="77"/>
<connect gate="C" pin="VCC" pad="111"/>
<connect gate="C" pin="VCCIO_0" pad="131"/>
<connect gate="C" pin="VCCIO_0_2" pad="123"/>
<connect gate="C" pin="VCCIO_1" pad="100"/>
<connect gate="C" pin="VCCIO_1_2" pad="89"/>
<connect gate="C" pin="VCCIO_2" pad="57"/>
<connect gate="C" pin="VCCIO_2_2" pad="46"/>
<connect gate="C" pin="VCCIO_3" pad="30"/>
<connect gate="C" pin="VCCIO_3_2" pad="6"/>
<connect gate="C" pin="VCCPLL0" pad="54"/>
<connect gate="C" pin="VCCPLL1" pad="126"/>
<connect gate="C" pin="VCC_2" pad="27"/>
<connect gate="C" pin="VCC_3" pad="40"/>
<connect gate="C" pin="VCC_4" pad="92"/>
<connect gate="C" pin="VCC_SPI" pad="72"/>
<connect gate="C" pin="VPP_2V5" pad="108"/>
<connect gate="C" pin="VPP_FAST" pad="109"/>
</connects>
<technologies>
<technology name="">
<attribute name="MANUFACTURER_PART_NUMBER" value="ICE40HX4KTQ144" constant="no"/>
<attribute name="VENDOR" value="Lattice" constant="no"/>
</technology>
</technologies>
</device>
</devices>
</deviceset>
</devicesets>
</library>
</libraries>
<attributes>
</attributes>
<variantdefs>
</variantdefs>
<classes>
<class number="0" name="default" width="0" drill="0">
</class>
</classes>
<parts>
<part name="IC1" library="MotionDetectorCamera" deviceset="MT48LC16M16A2" device="" package3d_urn="urn:adsk.eagle:package:18739/1"/>
<part name="U1" library="MotionDetectorCamera" deviceset="ICE40HX4K-TQ144" device=""/>
</parts>
<sheets>
<sheet>
<plain>
</plain>
<instances>
<instance part="IC1" gate="G$1" x="218.44" y="58.42" smashed="yes">
<attribute name="NAME" x="208.28" y="87.63" size="1.778" layer="95"/>
<attribute name="VALUE" x="208.28" y="22.86" size="1.778" layer="96"/>
</instance>
<instance part="IC1" gate="P" x="254" y="63.5" smashed="yes">
<attribute name="NAME" x="248.92" y="87.63" size="1.778" layer="95"/>
<attribute name="VALUE" x="248.92" y="38.1" size="1.778" layer="96"/>
</instance>
<instance part="U1" gate="A" x="-81.28" y="104.14" smashed="yes">
<attribute name="NAME" x="-45.3644" y="115.7986" size="2.0828" layer="95" ratio="6" rot="SR0"/>
<attribute name="VALUE" x="-45.9994" y="113.2586" size="2.0828" layer="96" ratio="6" rot="SR0"/>
</instance>
<instance part="U1" gate="B" x="63.5" y="99.06" smashed="yes">
<attribute name="NAME" x="23.2156" y="105.6386" size="2.0828" layer="95" ratio="6" rot="SR0"/>
<attribute name="VALUE" x="22.5806" y="108.1786" size="2.0828" layer="96" ratio="6" rot="SR0"/>
</instance>
<instance part="U1" gate="C" x="86.36" y="101.6" smashed="yes">
<attribute name="NAME" x="109.5756" y="110.7186" size="2.0828" layer="95" ratio="6" rot="SR0"/>
<attribute name="VALUE" x="108.9406" y="108.1786" size="2.0828" layer="96" ratio="6" rot="SR0"/>
</instance>
</instances>
<busses>
</busses>
<nets>
</nets>
</sheet>
</sheets>
</schematic>
</drawing>
<compatibility>
<note version="8.3" severity="warning">
Since Version 8.3, EAGLE supports URNs for individual library
assets (packages, symbols, and devices). The URNs of those assets
will not be understood (or retained) with this version.
</note>
<note version="8.3" severity="warning">
Since Version 8.3, EAGLE supports the association of 3D packages
with devices in libraries, schematics, and board files. Those 3D
packages will not be understood (or retained) with this version.
</note>
</compatibility>
</eagle>
