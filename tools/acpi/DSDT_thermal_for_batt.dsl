/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20230628 (32-bit version)
 * Copyright (c) 2000 - 2023 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of ./DSDT.aml
 *
 * Original Table Header:
 *     Signature        "DSDT"
 *     Length           0x00000F01 (3841)
 *     Revision         0x02
 *     Checksum         0x18
 *     OEM ID           "QCOMM "
 *     OEM Table ID     "SM8550 "
 *     OEM Revision     0x00000003 (3)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20241212 (539234834)
 */
DefinitionBlock ("", "DSDT", 2, "QCOMM ", "SM8550 ", 0x00000003)
{
    Scope (_SB)
    {
        OperationRegion (DBG0, SystemMemory, 0xD7FF0000, 0x200)
        Field (DBG0, DWordAcc, NoLock, Preserve)
        {
            CNT0,   32,
            L00,   32,
            L01,   32,
            L02,   32,
            L03,   32,
            L04,   32,
            L05,   32,
            L06,   32,
            L07,   32,
            L08,   32,
            L09,   32,
            L10,   32,
            L11,   32,
            L12,   32,
            L13,   32,
            L14,   32,
            L15,   32,
            L16,   32,
            L17,   32,
            L18,   32,
            L19,   32,
            L20,   32,
            L21,   32,
            L22,   32,
            L23,   32,
            L24,   32,
            L25,   32,
            L26,   32,
            L27,   32,
            L28,   32,
            L29,   32,
            L30,   32,
            L31,   32,
            C00,   32,
            C01,   32,
            C02,   32,
            C03,   32,
            C04,   32,
            C05,   32,
            C06,   32,
            C07,   32,
            C08,   32,
            C09,   32,
            C10,   32,
            C11,   32,
            C12,   32,
            C13,   32,
            C14,   32,
            C15,   32,
            C16,   32,
            C17,   32,
            C18,   32,
            C19,   32,
            C20,   32,
            C21,   32,
            C22,   32,
            C23,   32,
            C24,   32,
            C25,   32,
            C26,   32,
            C27,   32,
            C28,   32,
            C29,   32,
            C30,   32,
            C31,   32
        }

        Method (DBGL, 1, NotSerialized)
        {
            Local0 = CNT0
            CNT0 = Local0 + 1
            Local1 = Local0 & 0x1F
            Local2 = (Timer << 8) | (Arg0 & 0xFF)
            If (Local1 == 0x00) { L00 = Local2 }
            If (Local1 == 0x01) { L01 = Local2 }
            If (Local1 == 0x02) { L02 = Local2 }
            If (Local1 == 0x03) { L03 = Local2 }
            If (Local1 == 0x04) { L04 = Local2 }
            If (Local1 == 0x05) { L05 = Local2 }
            If (Local1 == 0x06) { L06 = Local2 }
            If (Local1 == 0x07) { L07 = Local2 }
            If (Local1 == 0x08) { L08 = Local2 }
            If (Local1 == 0x09) { L09 = Local2 }
            If (Local1 == 0x0A) { L10 = Local2 }
            If (Local1 == 0x0B) { L11 = Local2 }
            If (Local1 == 0x0C) { L12 = Local2 }
            If (Local1 == 0x0D) { L13 = Local2 }
            If (Local1 == 0x0E) { L14 = Local2 }
            If (Local1 == 0x0F) { L15 = Local2 }
            If (Local1 == 0x10) { L16 = Local2 }
            If (Local1 == 0x11) { L17 = Local2 }
            If (Local1 == 0x12) { L18 = Local2 }
            If (Local1 == 0x13) { L19 = Local2 }
            If (Local1 == 0x14) { L20 = Local2 }
            If (Local1 == 0x15) { L21 = Local2 }
            If (Local1 == 0x16) { L22 = Local2 }
            If (Local1 == 0x17) { L23 = Local2 }
            If (Local1 == 0x18) { L24 = Local2 }
            If (Local1 == 0x19) { L25 = Local2 }
            If (Local1 == 0x1A) { L26 = Local2 }
            If (Local1 == 0x1B) { L27 = Local2 }
            If (Local1 == 0x1C) { L28 = Local2 }
            If (Local1 == 0x1D) { L29 = Local2 }
            If (Local1 == 0x1E) { L30 = Local2 }
            If (Local1 == 0x1F) { L31 = Local2 }
            Local3 = Arg0 & 0x1F
            If (Local3 == 0x00) { C00 = C00 + 1 }
            If (Local3 == 0x01) { C01 = C01 + 1 }
            If (Local3 == 0x02) { C02 = C02 + 1 }
            If (Local3 == 0x03) { C03 = C03 + 1 }
            If (Local3 == 0x04) { C04 = C04 + 1 }
            If (Local3 == 0x05) { C05 = C05 + 1 }
            If (Local3 == 0x06) { C06 = C06 + 1 }
            If (Local3 == 0x07) { C07 = C07 + 1 }
            If (Local3 == 0x08) { C08 = C08 + 1 }
            If (Local3 == 0x09) { C09 = C09 + 1 }
            If (Local3 == 0x0A) { C10 = C10 + 1 }
            If (Local3 == 0x0B) { C11 = C11 + 1 }
            If (Local3 == 0x0C) { C12 = C12 + 1 }
            If (Local3 == 0x0D) { C13 = C13 + 1 }
            If (Local3 == 0x0E) { C14 = C14 + 1 }
            If (Local3 == 0x0F) { C15 = C15 + 1 }
            If (Local3 == 0x10) { C16 = C16 + 1 }
            If (Local3 == 0x11) { C17 = C17 + 1 }
            If (Local3 == 0x12) { C18 = C18 + 1 }
            If (Local3 == 0x13) { C19 = C19 + 1 }
            If (Local3 == 0x14) { C20 = C20 + 1 }
            If (Local3 == 0x15) { C21 = C21 + 1 }
            If (Local3 == 0x16) { C22 = C22 + 1 }
            If (Local3 == 0x17) { C23 = C23 + 1 }
            If (Local3 == 0x18) { C24 = C24 + 1 }
            If (Local3 == 0x19) { C25 = C25 + 1 }
            If (Local3 == 0x1A) { C26 = C26 + 1 }
            If (Local3 == 0x1B) { C27 = C27 + 1 }
            If (Local3 == 0x1C) { C28 = C28 + 1 }
            If (Local3 == 0x1D) { C29 = C29 + 1 }
            If (Local3 == 0x1E) { C30 = C30 + 1 }
            If (Local3 == 0x1F) { C31 = C31 + 1 }
        }

        OperationRegion (UHC0, SystemMemory, 0x01D84000, 0xA0)
        Field (UHC0, DWordAcc, NoLock, Preserve)
        {
            Offset (0x20),
            IS__,   32,
            IE__,   32,
            Offset (0x30),
            HCS_,   32,
            HCE_,   32,
            ECPA,   32,
            ECDL,   32,
            ECN_,   32,
            ECT_,   32,
            Offset (0x50),
            TRLB,   32,
            TRLU,   32,
            TRDB,   32,
            Offset (0x60),
            TRRS,   32,
            Offset (0x90),
            UIC_,   32,
            UA1_,   32,
            UA2_,   32
        }

        OperationRegion (SNP0, SystemMemory, 0xD7FF2000, 0xC10)
        Field (SNP0, DWordAcc, NoLock, Preserve)
        {
            SCLL,   32,
            STOR,   32,
            Offset (0x10),
            Q000,   32,
            Q001,   32,
            Q002,   32,
            Q003,   32,
            Q004,   32,
            Q005,   32,
            Q006,   32,
            Q007,   32,
            Q008,   32,
            Q009,   32,
            Q00A,   32,
            Q00B,   32,
            Q00C,   32,
            Q00D,   32,
            Q00E,   32,
            Q00F,   32,
            Q010,   32,
            Q011,   32,
            Q012,   32,
            Q013,   32,
            Q014,   32,
            Q015,   32,
            Q016,   32,
            Q017,   32,
            Q018,   32,
            Q019,   32,
            Q01A,   32,
            Q01B,   32,
            Q01C,   32,
            Q01D,   32,
            Q01E,   32,
            Q01F,   32,
            Q020,   32,
            Q021,   32,
            Q022,   32,
            Q023,   32,
            Q024,   32,
            Q025,   32,
            Q026,   32,
            Q027,   32,
            Q028,   32,
            Q029,   32,
            Q02A,   32,
            Q02B,   32,
            Q02C,   32,
            Q02D,   32,
            Q02E,   32,
            Q02F,   32,
            Q100,   32,
            Q101,   32,
            Q102,   32,
            Q103,   32,
            Q104,   32,
            Q105,   32,
            Q106,   32,
            Q107,   32,
            Q108,   32,
            Q109,   32,
            Q10A,   32,
            Q10B,   32,
            Q10C,   32,
            Q10D,   32,
            Q10E,   32,
            Q10F,   32,
            Q110,   32,
            Q111,   32,
            Q112,   32,
            Q113,   32,
            Q114,   32,
            Q115,   32,
            Q116,   32,
            Q117,   32,
            Q118,   32,
            Q119,   32,
            Q11A,   32,
            Q11B,   32,
            Q11C,   32,
            Q11D,   32,
            Q11E,   32,
            Q11F,   32,
            Q120,   32,
            Q121,   32,
            Q122,   32,
            Q123,   32,
            Q124,   32,
            Q125,   32,
            Q126,   32,
            Q127,   32,
            Q128,   32,
            Q129,   32,
            Q12A,   32,
            Q12B,   32,
            Q12C,   32,
            Q12D,   32,
            Q12E,   32,
            Q12F,   32,
            Q200,   32,
            Q201,   32,
            Q202,   32,
            Q203,   32,
            Q204,   32,
            Q205,   32,
            Q206,   32,
            Q207,   32,
            Q208,   32,
            Q209,   32,
            Q20A,   32,
            Q20B,   32,
            Q20C,   32,
            Q20D,   32,
            Q20E,   32,
            Q20F,   32,
            Q210,   32,
            Q211,   32,
            Q212,   32,
            Q213,   32,
            Q214,   32,
            Q215,   32,
            Q216,   32,
            Q217,   32,
            Q218,   32,
            Q219,   32,
            Q21A,   32,
            Q21B,   32,
            Q21C,   32,
            Q21D,   32,
            Q21E,   32,
            Q21F,   32,
            Q220,   32,
            Q221,   32,
            Q222,   32,
            Q223,   32,
            Q224,   32,
            Q225,   32,
            Q226,   32,
            Q227,   32,
            Q228,   32,
            Q229,   32,
            Q22A,   32,
            Q22B,   32,
            Q22C,   32,
            Q22D,   32,
            Q22E,   32,
            Q22F,   32,
            Q300,   32,
            Q301,   32,
            Q302,   32,
            Q303,   32,
            Q304,   32,
            Q305,   32,
            Q306,   32,
            Q307,   32,
            Q308,   32,
            Q309,   32,
            Q30A,   32,
            Q30B,   32,
            Q30C,   32,
            Q30D,   32,
            Q30E,   32,
            Q30F,   32,
            Q310,   32,
            Q311,   32,
            Q312,   32,
            Q313,   32,
            Q314,   32,
            Q315,   32,
            Q316,   32,
            Q317,   32,
            Q318,   32,
            Q319,   32,
            Q31A,   32,
            Q31B,   32,
            Q31C,   32,
            Q31D,   32,
            Q31E,   32,
            Q31F,   32,
            Q320,   32,
            Q321,   32,
            Q322,   32,
            Q323,   32,
            Q324,   32,
            Q325,   32,
            Q326,   32,
            Q327,   32,
            Q328,   32,
            Q329,   32,
            Q32A,   32,
            Q32B,   32,
            Q32C,   32,
            Q32D,   32,
            Q32E,   32,
            Q32F,   32,
            Q400,   32,
            Q401,   32,
            Q402,   32,
            Q403,   32,
            Q404,   32,
            Q405,   32,
            Q406,   32,
            Q407,   32,
            Q408,   32,
            Q409,   32,
            Q40A,   32,
            Q40B,   32,
            Q40C,   32,
            Q40D,   32,
            Q40E,   32,
            Q40F,   32,
            Q410,   32,
            Q411,   32,
            Q412,   32,
            Q413,   32,
            Q414,   32,
            Q415,   32,
            Q416,   32,
            Q417,   32,
            Q418,   32,
            Q419,   32,
            Q41A,   32,
            Q41B,   32,
            Q41C,   32,
            Q41D,   32,
            Q41E,   32,
            Q41F,   32,
            Q420,   32,
            Q421,   32,
            Q422,   32,
            Q423,   32,
            Q424,   32,
            Q425,   32,
            Q426,   32,
            Q427,   32,
            Q428,   32,
            Q429,   32,
            Q42A,   32,
            Q42B,   32,
            Q42C,   32,
            Q42D,   32,
            Q42E,   32,
            Q42F,   32,
            Q500,   32,
            Q501,   32,
            Q502,   32,
            Q503,   32,
            Q504,   32,
            Q505,   32,
            Q506,   32,
            Q507,   32,
            Q508,   32,
            Q509,   32,
            Q50A,   32,
            Q50B,   32,
            Q50C,   32,
            Q50D,   32,
            Q50E,   32,
            Q50F,   32,
            Q510,   32,
            Q511,   32,
            Q512,   32,
            Q513,   32,
            Q514,   32,
            Q515,   32,
            Q516,   32,
            Q517,   32,
            Q518,   32,
            Q519,   32,
            Q51A,   32,
            Q51B,   32,
            Q51C,   32,
            Q51D,   32,
            Q51E,   32,
            Q51F,   32,
            Q520,   32,
            Q521,   32,
            Q522,   32,
            Q523,   32,
            Q524,   32,
            Q525,   32,
            Q526,   32,
            Q527,   32,
            Q528,   32,
            Q529,   32,
            Q52A,   32,
            Q52B,   32,
            Q52C,   32,
            Q52D,   32,
            Q52E,   32,
            Q52F,   32,
            Q600,   32,
            Q601,   32,
            Q602,   32,
            Q603,   32,
            Q604,   32,
            Q605,   32,
            Q606,   32,
            Q607,   32,
            Q608,   32,
            Q609,   32,
            Q60A,   32,
            Q60B,   32,
            Q60C,   32,
            Q60D,   32,
            Q60E,   32,
            Q60F,   32,
            Q610,   32,
            Q611,   32,
            Q612,   32,
            Q613,   32,
            Q614,   32,
            Q615,   32,
            Q616,   32,
            Q617,   32,
            Q618,   32,
            Q619,   32,
            Q61A,   32,
            Q61B,   32,
            Q61C,   32,
            Q61D,   32,
            Q61E,   32,
            Q61F,   32,
            Q620,   32,
            Q621,   32,
            Q622,   32,
            Q623,   32,
            Q624,   32,
            Q625,   32,
            Q626,   32,
            Q627,   32,
            Q628,   32,
            Q629,   32,
            Q62A,   32,
            Q62B,   32,
            Q62C,   32,
            Q62D,   32,
            Q62E,   32,
            Q62F,   32,
            Q700,   32,
            Q701,   32,
            Q702,   32,
            Q703,   32,
            Q704,   32,
            Q705,   32,
            Q706,   32,
            Q707,   32,
            Q708,   32,
            Q709,   32,
            Q70A,   32,
            Q70B,   32,
            Q70C,   32,
            Q70D,   32,
            Q70E,   32,
            Q70F,   32,
            Q710,   32,
            Q711,   32,
            Q712,   32,
            Q713,   32,
            Q714,   32,
            Q715,   32,
            Q716,   32,
            Q717,   32,
            Q718,   32,
            Q719,   32,
            Q71A,   32,
            Q71B,   32,
            Q71C,   32,
            Q71D,   32,
            Q71E,   32,
            Q71F,   32,
            Q720,   32,
            Q721,   32,
            Q722,   32,
            Q723,   32,
            Q724,   32,
            Q725,   32,
            Q726,   32,
            Q727,   32,
            Q728,   32,
            Q729,   32,
            Q72A,   32,
            Q72B,   32,
            Q72C,   32,
            Q72D,   32,
            Q72E,   32,
            Q72F,   32,
            Q800,   32,
            Q801,   32,
            Q802,   32,
            Q803,   32,
            Q804,   32,
            Q805,   32,
            Q806,   32,
            Q807,   32,
            Q808,   32,
            Q809,   32,
            Q80A,   32,
            Q80B,   32,
            Q80C,   32,
            Q80D,   32,
            Q80E,   32,
            Q80F,   32,
            Q810,   32,
            Q811,   32,
            Q812,   32,
            Q813,   32,
            Q814,   32,
            Q815,   32,
            Q816,   32,
            Q817,   32,
            Q818,   32,
            Q819,   32,
            Q81A,   32,
            Q81B,   32,
            Q81C,   32,
            Q81D,   32,
            Q81E,   32,
            Q81F,   32,
            Q820,   32,
            Q821,   32,
            Q822,   32,
            Q823,   32,
            Q824,   32,
            Q825,   32,
            Q826,   32,
            Q827,   32,
            Q828,   32,
            Q829,   32,
            Q82A,   32,
            Q82B,   32,
            Q82C,   32,
            Q82D,   32,
            Q82E,   32,
            Q82F,   32,
            Q900,   32,
            Q901,   32,
            Q902,   32,
            Q903,   32,
            Q904,   32,
            Q905,   32,
            Q906,   32,
            Q907,   32,
            Q908,   32,
            Q909,   32,
            Q90A,   32,
            Q90B,   32,
            Q90C,   32,
            Q90D,   32,
            Q90E,   32,
            Q90F,   32,
            Q910,   32,
            Q911,   32,
            Q912,   32,
            Q913,   32,
            Q914,   32,
            Q915,   32,
            Q916,   32,
            Q917,   32,
            Q918,   32,
            Q919,   32,
            Q91A,   32,
            Q91B,   32,
            Q91C,   32,
            Q91D,   32,
            Q91E,   32,
            Q91F,   32,
            Q920,   32,
            Q921,   32,
            Q922,   32,
            Q923,   32,
            Q924,   32,
            Q925,   32,
            Q926,   32,
            Q927,   32,
            Q928,   32,
            Q929,   32,
            Q92A,   32,
            Q92B,   32,
            Q92C,   32,
            Q92D,   32,
            Q92E,   32,
            Q92F,   32,
            QA00,   32,
            QA01,   32,
            QA02,   32,
            QA03,   32,
            QA04,   32,
            QA05,   32,
            QA06,   32,
            QA07,   32,
            QA08,   32,
            QA09,   32,
            QA0A,   32,
            QA0B,   32,
            QA0C,   32,
            QA0D,   32,
            QA0E,   32,
            QA0F,   32,
            QA10,   32,
            QA11,   32,
            QA12,   32,
            QA13,   32,
            QA14,   32,
            QA15,   32,
            QA16,   32,
            QA17,   32,
            QA18,   32,
            QA19,   32,
            QA1A,   32,
            QA1B,   32,
            QA1C,   32,
            QA1D,   32,
            QA1E,   32,
            QA1F,   32,
            QA20,   32,
            QA21,   32,
            QA22,   32,
            QA23,   32,
            QA24,   32,
            QA25,   32,
            QA26,   32,
            QA27,   32,
            QA28,   32,
            QA29,   32,
            QA2A,   32,
            QA2B,   32,
            QA2C,   32,
            QA2D,   32,
            QA2E,   32,
            QA2F,   32,
            QB00,   32,
            QB01,   32,
            QB02,   32,
            QB03,   32,
            QB04,   32,
            QB05,   32,
            QB06,   32,
            QB07,   32,
            QB08,   32,
            QB09,   32,
            QB0A,   32,
            QB0B,   32,
            QB0C,   32,
            QB0D,   32,
            QB0E,   32,
            QB0F,   32,
            QB10,   32,
            QB11,   32,
            QB12,   32,
            QB13,   32,
            QB14,   32,
            QB15,   32,
            QB16,   32,
            QB17,   32,
            QB18,   32,
            QB19,   32,
            QB1A,   32,
            QB1B,   32,
            QB1C,   32,
            QB1D,   32,
            QB1E,   32,
            QB1F,   32,
            QB20,   32,
            QB21,   32,
            QB22,   32,
            QB23,   32,
            QB24,   32,
            QB25,   32,
            QB26,   32,
            QB27,   32,
            QB28,   32,
            QB29,   32,
            QB2A,   32,
            QB2B,   32,
            QB2C,   32,
            QB2D,   32,
            QB2E,   32,
            QB2F,   32,
            QC00,   32,
            QC01,   32,
            QC02,   32,
            QC03,   32,
            QC04,   32,
            QC05,   32,
            QC06,   32,
            QC07,   32,
            QC08,   32,
            QC09,   32,
            QC0A,   32,
            QC0B,   32,
            QC0C,   32,
            QC0D,   32,
            QC0E,   32,
            QC0F,   32,
            QC10,   32,
            QC11,   32,
            QC12,   32,
            QC13,   32,
            QC14,   32,
            QC15,   32,
            QC16,   32,
            QC17,   32,
            QC18,   32,
            QC19,   32,
            QC1A,   32,
            QC1B,   32,
            QC1C,   32,
            QC1D,   32,
            QC1E,   32,
            QC1F,   32,
            QC20,   32,
            QC21,   32,
            QC22,   32,
            QC23,   32,
            QC24,   32,
            QC25,   32,
            QC26,   32,
            QC27,   32,
            QC28,   32,
            QC29,   32,
            QC2A,   32,
            QC2B,   32,
            QC2C,   32,
            QC2D,   32,
            QC2E,   32,
            QC2F,   32,
            QD00,   32,
            QD01,   32,
            QD02,   32,
            QD03,   32,
            QD04,   32,
            QD05,   32,
            QD06,   32,
            QD07,   32,
            QD08,   32,
            QD09,   32,
            QD0A,   32,
            QD0B,   32,
            QD0C,   32,
            QD0D,   32,
            QD0E,   32,
            QD0F,   32,
            QD10,   32,
            QD11,   32,
            QD12,   32,
            QD13,   32,
            QD14,   32,
            QD15,   32,
            QD16,   32,
            QD17,   32,
            QD18,   32,
            QD19,   32,
            QD1A,   32,
            QD1B,   32,
            QD1C,   32,
            QD1D,   32,
            QD1E,   32,
            QD1F,   32,
            QD20,   32,
            QD21,   32,
            QD22,   32,
            QD23,   32,
            QD24,   32,
            QD25,   32,
            QD26,   32,
            QD27,   32,
            QD28,   32,
            QD29,   32,
            QD2A,   32,
            QD2B,   32,
            QD2C,   32,
            QD2D,   32,
            QD2E,   32,
            QD2F,   32,
            QE00,   32,
            QE01,   32,
            QE02,   32,
            QE03,   32,
            QE04,   32,
            QE05,   32,
            QE06,   32,
            QE07,   32,
            QE08,   32,
            QE09,   32,
            QE0A,   32,
            QE0B,   32,
            QE0C,   32,
            QE0D,   32,
            QE0E,   32,
            QE0F,   32,
            QE10,   32,
            QE11,   32,
            QE12,   32,
            QE13,   32,
            QE14,   32,
            QE15,   32,
            QE16,   32,
            QE17,   32,
            QE18,   32,
            QE19,   32,
            QE1A,   32,
            QE1B,   32,
            QE1C,   32,
            QE1D,   32,
            QE1E,   32,
            QE1F,   32,
            QE20,   32,
            QE21,   32,
            QE22,   32,
            QE23,   32,
            QE24,   32,
            QE25,   32,
            QE26,   32,
            QE27,   32,
            QE28,   32,
            QE29,   32,
            QE2A,   32,
            QE2B,   32,
            QE2C,   32,
            QE2D,   32,
            QE2E,   32,
            QE2F,   32,
            QF00,   32,
            QF01,   32,
            QF02,   32,
            QF03,   32,
            QF04,   32,
            QF05,   32,
            QF06,   32,
            QF07,   32,
            QF08,   32,
            QF09,   32,
            QF0A,   32,
            QF0B,   32,
            QF0C,   32,
            QF0D,   32,
            QF0E,   32,
            QF0F,   32,
            QF10,   32,
            QF11,   32,
            QF12,   32,
            QF13,   32,
            QF14,   32,
            QF15,   32,
            QF16,   32,
            QF17,   32,
            QF18,   32,
            QF19,   32,
            QF1A,   32,
            QF1B,   32,
            QF1C,   32,
            QF1D,   32,
            QF1E,   32,
            QF1F,   32,
            QF20,   32,
            QF21,   32,
            QF22,   32,
            QF23,   32,
            QF24,   32,
            QF25,   32,
            QF26,   32,
            QF27,   32,
            QF28,   32,
            QF29,   32,
            QF2A,   32,
            QF2B,   32,
            QF2C,   32,
            QF2D,   32,
            QF2E,   32,
            QF2F,   32
        }

        Name (V00_, 0xFFFFFFFF)
        Name (V01_, 0xFFFFFFFF)
        Name (V02_, 0xFFFFFFFF)
        Name (V03_, 0xFFFFFFFF)
        Name (V04_, 0xFFFFFFFF)
        Name (V05_, 0xFFFFFFFF)
        Name (V06_, 0xFFFFFFFF)
        Name (V07_, 0xFFFFFFFF)
        Name (V08_, 0xFFFFFFFF)
        Name (V09_, 0xFFFFFFFF)
        Name (V10_, 0xFFFFFFFF)
        Name (V11_, 0xFFFFFFFF)
        Name (V12_, 0xFFFFFFFF)
        Name (V13_, 0xFFFFFFFF)
        Name (V14_, 0xFFFFFFFF)
        Name (E00_, 0xFFFFFFFF)
        Name (E01_, 0xFFFFFFFF)
        Name (E02_, 0xFFFFFFFF)
        Name (E03_, 0xFFFFFFFF)
        Name (E04_, 0xFFFFFFFF)
        Name (E05_, 0xFFFFFFFF)
        Name (E06_, 0xFFFFFFFF)
        Name (E07_, 0xFFFFFFFF)
        Name (E08_, 0xFFFFFFFF)
        Name (E09_, 0xFFFFFFFF)
        Name (E10_, 0xFFFFFFFF)
        Name (E11_, 0xFFFFFFFF)
        Name (E12_, 0xFFFFFFFF)
        Name (E13_, 0xFFFFFFFF)
        Name (E14_, 0xFFFFFFFF)
        Name (E15_, 0xFFFFFFFF)
        Name (E16_, 0xFFFFFFFF)
        Name (E17_, 0xFFFFFFFF)
        Name (E18_, 0xFFFFFFFF)
        Name (E19_, 0xFFFFFFFF)
        Name (E20_, 0xFFFFFFFF)
        Name (E21_, 0xFFFFFFFF)

        Method (UFSS, 0, NotSerialized)
        {
            SCLL = SCLL + 1
            Local0 = (HCE_ ^ V00_) | (HCS_ ^ V01_) | (IS__ ^ V02_) | (IE__ ^ V03_) | (ECPA ^ V04_) | (ECDL ^ V05_) | (ECN_ ^ V06_) | (ECT_ ^ V07_) | (TRLB ^ V08_) | (TRLU ^ V09_) | (TRDB ^ V10_) | (TRRS ^ V11_) | (UIC_ ^ V12_) | (UA1_ ^ V13_) | (UA2_ ^ V14_)
            If (Local0 != Zero)
            {
                Local2 = Timer & 0xFFFFFFFF
                Local1 = STOR & 0x0F
                E00_ = 0xFFFFFFFF
                E11_ = 0xFFFFFFFF
If (Local1 == 0x00)
            {
                Q000 = Local2
                Q001 = HCE_
                Q002 = HCS_
                Q003 = IS__
                Q004 = IE__
                Q005 = ECPA
                Q006 = ECDL
                Q007 = ECN_
                Q008 = ECT_
                Q009 = TRLB
                Q00A = TRLU
                Q00B = TRDB
                Q00C = TRRS
                Q00D = UIC_
                Q00E = UA1_
                Q00F = UA2_
                Q010 = E00_
                Q011 = E01_
                Q012 = E02_
                Q013 = E03_
                Q014 = E04_
                Q015 = E05_
                Q016 = E06_
                Q017 = E07_
                Q018 = E08_
                Q019 = E09_
                Q01A = E10_
                Q01B = E11_
                Q01C = E12_
                Q01D = E13_
                Q01E = E14_
                Q01F = E15_
                Q020 = E16_
                Q021 = E17_
                Q022 = E18_
                Q023 = E19_
                Q024 = E20_
                Q025 = E21_
            }
            If (Local1 == 0x01)
            {
                Q100 = Local2
                Q101 = HCE_
                Q102 = HCS_
                Q103 = IS__
                Q104 = IE__
                Q105 = ECPA
                Q106 = ECDL
                Q107 = ECN_
                Q108 = ECT_
                Q109 = TRLB
                Q10A = TRLU
                Q10B = TRDB
                Q10C = TRRS
                Q10D = UIC_
                Q10E = UA1_
                Q10F = UA2_
                Q110 = E00_
                Q111 = E01_
                Q112 = E02_
                Q113 = E03_
                Q114 = E04_
                Q115 = E05_
                Q116 = E06_
                Q117 = E07_
                Q118 = E08_
                Q119 = E09_
                Q11A = E10_
                Q11B = E11_
                Q11C = E12_
                Q11D = E13_
                Q11E = E14_
                Q11F = E15_
                Q120 = E16_
                Q121 = E17_
                Q122 = E18_
                Q123 = E19_
                Q124 = E20_
                Q125 = E21_
            }
            If (Local1 == 0x02)
            {
                Q200 = Local2
                Q201 = HCE_
                Q202 = HCS_
                Q203 = IS__
                Q204 = IE__
                Q205 = ECPA
                Q206 = ECDL
                Q207 = ECN_
                Q208 = ECT_
                Q209 = TRLB
                Q20A = TRLU
                Q20B = TRDB
                Q20C = TRRS
                Q20D = UIC_
                Q20E = UA1_
                Q20F = UA2_
                Q210 = E00_
                Q211 = E01_
                Q212 = E02_
                Q213 = E03_
                Q214 = E04_
                Q215 = E05_
                Q216 = E06_
                Q217 = E07_
                Q218 = E08_
                Q219 = E09_
                Q21A = E10_
                Q21B = E11_
                Q21C = E12_
                Q21D = E13_
                Q21E = E14_
                Q21F = E15_
                Q220 = E16_
                Q221 = E17_
                Q222 = E18_
                Q223 = E19_
                Q224 = E20_
                Q225 = E21_
            }
            If (Local1 == 0x03)
            {
                Q300 = Local2
                Q301 = HCE_
                Q302 = HCS_
                Q303 = IS__
                Q304 = IE__
                Q305 = ECPA
                Q306 = ECDL
                Q307 = ECN_
                Q308 = ECT_
                Q309 = TRLB
                Q30A = TRLU
                Q30B = TRDB
                Q30C = TRRS
                Q30D = UIC_
                Q30E = UA1_
                Q30F = UA2_
                Q310 = E00_
                Q311 = E01_
                Q312 = E02_
                Q313 = E03_
                Q314 = E04_
                Q315 = E05_
                Q316 = E06_
                Q317 = E07_
                Q318 = E08_
                Q319 = E09_
                Q31A = E10_
                Q31B = E11_
                Q31C = E12_
                Q31D = E13_
                Q31E = E14_
                Q31F = E15_
                Q320 = E16_
                Q321 = E17_
                Q322 = E18_
                Q323 = E19_
                Q324 = E20_
                Q325 = E21_
            }
            If (Local1 == 0x04)
            {
                Q400 = Local2
                Q401 = HCE_
                Q402 = HCS_
                Q403 = IS__
                Q404 = IE__
                Q405 = ECPA
                Q406 = ECDL
                Q407 = ECN_
                Q408 = ECT_
                Q409 = TRLB
                Q40A = TRLU
                Q40B = TRDB
                Q40C = TRRS
                Q40D = UIC_
                Q40E = UA1_
                Q40F = UA2_
                Q410 = E00_
                Q411 = E01_
                Q412 = E02_
                Q413 = E03_
                Q414 = E04_
                Q415 = E05_
                Q416 = E06_
                Q417 = E07_
                Q418 = E08_
                Q419 = E09_
                Q41A = E10_
                Q41B = E11_
                Q41C = E12_
                Q41D = E13_
                Q41E = E14_
                Q41F = E15_
                Q420 = E16_
                Q421 = E17_
                Q422 = E18_
                Q423 = E19_
                Q424 = E20_
                Q425 = E21_
            }
            If (Local1 == 0x05)
            {
                Q500 = Local2
                Q501 = HCE_
                Q502 = HCS_
                Q503 = IS__
                Q504 = IE__
                Q505 = ECPA
                Q506 = ECDL
                Q507 = ECN_
                Q508 = ECT_
                Q509 = TRLB
                Q50A = TRLU
                Q50B = TRDB
                Q50C = TRRS
                Q50D = UIC_
                Q50E = UA1_
                Q50F = UA2_
                Q510 = E00_
                Q511 = E01_
                Q512 = E02_
                Q513 = E03_
                Q514 = E04_
                Q515 = E05_
                Q516 = E06_
                Q517 = E07_
                Q518 = E08_
                Q519 = E09_
                Q51A = E10_
                Q51B = E11_
                Q51C = E12_
                Q51D = E13_
                Q51E = E14_
                Q51F = E15_
                Q520 = E16_
                Q521 = E17_
                Q522 = E18_
                Q523 = E19_
                Q524 = E20_
                Q525 = E21_
            }
            If (Local1 == 0x06)
            {
                Q600 = Local2
                Q601 = HCE_
                Q602 = HCS_
                Q603 = IS__
                Q604 = IE__
                Q605 = ECPA
                Q606 = ECDL
                Q607 = ECN_
                Q608 = ECT_
                Q609 = TRLB
                Q60A = TRLU
                Q60B = TRDB
                Q60C = TRRS
                Q60D = UIC_
                Q60E = UA1_
                Q60F = UA2_
                Q610 = E00_
                Q611 = E01_
                Q612 = E02_
                Q613 = E03_
                Q614 = E04_
                Q615 = E05_
                Q616 = E06_
                Q617 = E07_
                Q618 = E08_
                Q619 = E09_
                Q61A = E10_
                Q61B = E11_
                Q61C = E12_
                Q61D = E13_
                Q61E = E14_
                Q61F = E15_
                Q620 = E16_
                Q621 = E17_
                Q622 = E18_
                Q623 = E19_
                Q624 = E20_
                Q625 = E21_
            }
            If (Local1 == 0x07)
            {
                Q700 = Local2
                Q701 = HCE_
                Q702 = HCS_
                Q703 = IS__
                Q704 = IE__
                Q705 = ECPA
                Q706 = ECDL
                Q707 = ECN_
                Q708 = ECT_
                Q709 = TRLB
                Q70A = TRLU
                Q70B = TRDB
                Q70C = TRRS
                Q70D = UIC_
                Q70E = UA1_
                Q70F = UA2_
                Q710 = E00_
                Q711 = E01_
                Q712 = E02_
                Q713 = E03_
                Q714 = E04_
                Q715 = E05_
                Q716 = E06_
                Q717 = E07_
                Q718 = E08_
                Q719 = E09_
                Q71A = E10_
                Q71B = E11_
                Q71C = E12_
                Q71D = E13_
                Q71E = E14_
                Q71F = E15_
                Q720 = E16_
                Q721 = E17_
                Q722 = E18_
                Q723 = E19_
                Q724 = E20_
                Q725 = E21_
            }
            If (Local1 == 0x08)
            {
                Q800 = Local2
                Q801 = HCE_
                Q802 = HCS_
                Q803 = IS__
                Q804 = IE__
                Q805 = ECPA
                Q806 = ECDL
                Q807 = ECN_
                Q808 = ECT_
                Q809 = TRLB
                Q80A = TRLU
                Q80B = TRDB
                Q80C = TRRS
                Q80D = UIC_
                Q80E = UA1_
                Q80F = UA2_
                Q810 = E00_
                Q811 = E01_
                Q812 = E02_
                Q813 = E03_
                Q814 = E04_
                Q815 = E05_
                Q816 = E06_
                Q817 = E07_
                Q818 = E08_
                Q819 = E09_
                Q81A = E10_
                Q81B = E11_
                Q81C = E12_
                Q81D = E13_
                Q81E = E14_
                Q81F = E15_
                Q820 = E16_
                Q821 = E17_
                Q822 = E18_
                Q823 = E19_
                Q824 = E20_
                Q825 = E21_
            }
            If (Local1 == 0x09)
            {
                Q900 = Local2
                Q901 = HCE_
                Q902 = HCS_
                Q903 = IS__
                Q904 = IE__
                Q905 = ECPA
                Q906 = ECDL
                Q907 = ECN_
                Q908 = ECT_
                Q909 = TRLB
                Q90A = TRLU
                Q90B = TRDB
                Q90C = TRRS
                Q90D = UIC_
                Q90E = UA1_
                Q90F = UA2_
                Q910 = E00_
                Q911 = E01_
                Q912 = E02_
                Q913 = E03_
                Q914 = E04_
                Q915 = E05_
                Q916 = E06_
                Q917 = E07_
                Q918 = E08_
                Q919 = E09_
                Q91A = E10_
                Q91B = E11_
                Q91C = E12_
                Q91D = E13_
                Q91E = E14_
                Q91F = E15_
                Q920 = E16_
                Q921 = E17_
                Q922 = E18_
                Q923 = E19_
                Q924 = E20_
                Q925 = E21_
            }
            If (Local1 == 0x0A)
            {
                QA00 = Local2
                QA01 = HCE_
                QA02 = HCS_
                QA03 = IS__
                QA04 = IE__
                QA05 = ECPA
                QA06 = ECDL
                QA07 = ECN_
                QA08 = ECT_
                QA09 = TRLB
                QA0A = TRLU
                QA0B = TRDB
                QA0C = TRRS
                QA0D = UIC_
                QA0E = UA1_
                QA0F = UA2_
                QA10 = E00_
                QA11 = E01_
                QA12 = E02_
                QA13 = E03_
                QA14 = E04_
                QA15 = E05_
                QA16 = E06_
                QA17 = E07_
                QA18 = E08_
                QA19 = E09_
                QA1A = E10_
                QA1B = E11_
                QA1C = E12_
                QA1D = E13_
                QA1E = E14_
                QA1F = E15_
                QA20 = E16_
                QA21 = E17_
                QA22 = E18_
                QA23 = E19_
                QA24 = E20_
                QA25 = E21_
            }
            If (Local1 == 0x0B)
            {
                QB00 = Local2
                QB01 = HCE_
                QB02 = HCS_
                QB03 = IS__
                QB04 = IE__
                QB05 = ECPA
                QB06 = ECDL
                QB07 = ECN_
                QB08 = ECT_
                QB09 = TRLB
                QB0A = TRLU
                QB0B = TRDB
                QB0C = TRRS
                QB0D = UIC_
                QB0E = UA1_
                QB0F = UA2_
                QB10 = E00_
                QB11 = E01_
                QB12 = E02_
                QB13 = E03_
                QB14 = E04_
                QB15 = E05_
                QB16 = E06_
                QB17 = E07_
                QB18 = E08_
                QB19 = E09_
                QB1A = E10_
                QB1B = E11_
                QB1C = E12_
                QB1D = E13_
                QB1E = E14_
                QB1F = E15_
                QB20 = E16_
                QB21 = E17_
                QB22 = E18_
                QB23 = E19_
                QB24 = E20_
                QB25 = E21_
            }
            If (Local1 == 0x0C)
            {
                QC00 = Local2
                QC01 = HCE_
                QC02 = HCS_
                QC03 = IS__
                QC04 = IE__
                QC05 = ECPA
                QC06 = ECDL
                QC07 = ECN_
                QC08 = ECT_
                QC09 = TRLB
                QC0A = TRLU
                QC0B = TRDB
                QC0C = TRRS
                QC0D = UIC_
                QC0E = UA1_
                QC0F = UA2_
                QC10 = E00_
                QC11 = E01_
                QC12 = E02_
                QC13 = E03_
                QC14 = E04_
                QC15 = E05_
                QC16 = E06_
                QC17 = E07_
                QC18 = E08_
                QC19 = E09_
                QC1A = E10_
                QC1B = E11_
                QC1C = E12_
                QC1D = E13_
                QC1E = E14_
                QC1F = E15_
                QC20 = E16_
                QC21 = E17_
                QC22 = E18_
                QC23 = E19_
                QC24 = E20_
                QC25 = E21_
            }
            If (Local1 == 0x0D)
            {
                QD00 = Local2
                QD01 = HCE_
                QD02 = HCS_
                QD03 = IS__
                QD04 = IE__
                QD05 = ECPA
                QD06 = ECDL
                QD07 = ECN_
                QD08 = ECT_
                QD09 = TRLB
                QD0A = TRLU
                QD0B = TRDB
                QD0C = TRRS
                QD0D = UIC_
                QD0E = UA1_
                QD0F = UA2_
                QD10 = E00_
                QD11 = E01_
                QD12 = E02_
                QD13 = E03_
                QD14 = E04_
                QD15 = E05_
                QD16 = E06_
                QD17 = E07_
                QD18 = E08_
                QD19 = E09_
                QD1A = E10_
                QD1B = E11_
                QD1C = E12_
                QD1D = E13_
                QD1E = E14_
                QD1F = E15_
                QD20 = E16_
                QD21 = E17_
                QD22 = E18_
                QD23 = E19_
                QD24 = E20_
                QD25 = E21_
            }
            If (Local1 == 0x0E)
            {
                QE00 = Local2
                QE01 = HCE_
                QE02 = HCS_
                QE03 = IS__
                QE04 = IE__
                QE05 = ECPA
                QE06 = ECDL
                QE07 = ECN_
                QE08 = ECT_
                QE09 = TRLB
                QE0A = TRLU
                QE0B = TRDB
                QE0C = TRRS
                QE0D = UIC_
                QE0E = UA1_
                QE0F = UA2_
                QE10 = E00_
                QE11 = E01_
                QE12 = E02_
                QE13 = E03_
                QE14 = E04_
                QE15 = E05_
                QE16 = E06_
                QE17 = E07_
                QE18 = E08_
                QE19 = E09_
                QE1A = E10_
                QE1B = E11_
                QE1C = E12_
                QE1D = E13_
                QE1E = E14_
                QE1F = E15_
                QE20 = E16_
                QE21 = E17_
                QE22 = E18_
                QE23 = E19_
                QE24 = E20_
                QE25 = E21_
            }
            If (Local1 == 0x0F)
            {
                QF00 = Local2
                QF01 = HCE_
                QF02 = HCS_
                QF03 = IS__
                QF04 = IE__
                QF05 = ECPA
                QF06 = ECDL
                QF07 = ECN_
                QF08 = ECT_
                QF09 = TRLB
                QF0A = TRLU
                QF0B = TRDB
                QF0C = TRRS
                QF0D = UIC_
                QF0E = UA1_
                QF0F = UA2_
                QF10 = E00_
                QF11 = E01_
                QF12 = E02_
                QF13 = E03_
                QF14 = E04_
                QF15 = E05_
                QF16 = E06_
                QF17 = E07_
                QF18 = E08_
                QF19 = E09_
                QF1A = E10_
                QF1B = E11_
                QF1C = E12_
                QF1D = E13_
                QF1E = E14_
                QF1F = E15_
                QF20 = E16_
                QF21 = E17_
                QF22 = E18_
                QF23 = E19_
                QF24 = E20_
                QF25 = E21_
            }
                STOR = STOR + 1
            V00_ = HCE_
            V01_ = HCS_
            V02_ = IS__
            V03_ = IE__
            V04_ = ECPA
            V05_ = ECDL
            V06_ = ECN_
            V07_ = ECT_
            V08_ = TRLB
            V09_ = TRLU
            V10_ = TRDB
            V11_ = TRRS
            V12_ = UIC_
            V13_ = UA1_
            V14_ = UA2_
            }
        }

        OperationRegion (TSN0, SystemMemory, 0x0C228000, 0x200)
        Field (TSN0, DWordAcc, NoLock, Preserve)
        {
            Offset (0xA0),
            T0S0,   32,
            T0S1,   32,
            T0S2,   32,
            T0S3,   32,
            T0S4,   32,
            T0S5,   32,
            T0S6,   32,
            T0S7,   32,
            T0S8,   32,
            T0S9,   32,
            T0SA,   32,
            T0SB,   32,
            T0SC,   32,
            T0SD,   32,
            T0SE,   32
        }
        OperationRegion (TSN1, SystemMemory, 0x0C229000, 0x200)
        Field (TSN1, DWordAcc, NoLock, Preserve)
        {
            Offset (0xA0),
            T1S0,   32,
            T1S1,   32,
            T1S2,   32,
            T1S3,   32,
            T1S4,   32,
            T1S5,   32,
            T1S6,   32,
            T1S7,   32,
            T1S8,   32,
            T1S9,   32,
            T1SA,   32,
            T1SB,   32,
            T1SC,   32,
            T1SD,   32,
            T1SE,   32,
            T1SF,   32
        }
        OperationRegion (TSN2, SystemMemory, 0x0C22A000, 0x200)
        Field (TSN2, DWordAcc, NoLock, Preserve)
        {
            Offset (0xA0),
            T2S0,   32,
            T2S1,   32,
            T2S2,   32,
            T2S3,   32,
            T2S4,   32,
            T2S5,   32,
            T2S6,   32,
            T2S7,   32,
            T2S8,   32,
            T2S9,   32,
            T2SA,   32,
            T2SB,   32,
            T2SC,   32
        }

        Method (TCNV, 1, NotSerialized)   // raw TSENS status -> deci-Kelvin (0 = invalid sample)
        {
            If ((Arg0 & 0x00200000) == Zero)
            {
                Return (Zero)
            }

            Local0 = Arg0 & 0x0FFF
            If ((Local0 & 0x0800) != Zero)
            {
                Return (2732)             // below 0 C: report 0 C
            }

            Return (Local0 + 2732)        // deci-C + 273.2 K
        }


        Method (_INI, 0, NotSerialized)  // _INI: Initialize
        {
            DBGL (0x01)
        }

        Name (PSUB, "MTP08550")
        Name (PEPI, Zero)
        Name (FPID, 0xFFFF)
        Name (SVMJ, 0xFFFF)
        Name (TCMA, 0xDEADBEEF)
        Name (TCML, 0xBEEFDEAD)
        Device (SYSM)
        {
            Name (_HID, "ACPI0010" /* Processor Container Device */)  // _HID: Hardware ID
            Name (_UID, 0x03)  // _UID: Unique ID
            Method (_LPI, 0, NotSerialized)  // _LPI: Low Power Idle States
            {
                DBGL (0x02)  // trace _LPI SYSM
                If (PEPI)
                {
                    Return (Package (0x06)
                    {
                        Zero, 
                        0x02000000, 
                        0x03, 
                        Package (0x0A)
                        {
                            0x1D4C, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            0x0100, 
                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "platform.SS1"
                        }, 

                        Package (0x0A)
                        {
                            0x1F40, 
                            0x0BB8, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            0x0200, 
                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "platform.SS2"
                        }, 

                        Package (0x0A)
                        {
                            0x2328, 
                            0x1388, 
                            One, 
                            0x20, 
                            Zero, 
                            Zero, 
                            0xC300, 
                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "platform.DRIPS"
                        }
                    })
                }
            }

            Device (CLS0)
            {
                Name (_HID, "ACPI0010" /* Processor Container Device */)  // _HID: Hardware ID
                Name (_UID, Zero)  // _UID: Unique ID
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                DBGL (0x03)  // trace _STA SYSM/CLS0
                    Return (0x0F)
                }

                Method (_LPI, 0, NotSerialized)  // _LPI: Low Power Idle States
                {
                DBGL (0x04)  // trace _LPI SYSM/CLS0
                    If (PEPI)
                    {
                        Return (Package (0x05)
                        {
                            Zero, 
                            0x01000000, 
                            0x02, 
                            Package (0x0A)
                            {
                                0x09C4, 
                                0x01F4, 
                                One, 
                                Zero, 
                                Zero, 
                                Zero, 
                                0x40, 
                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                "Cluster0.CL4"
                            }, 

                            Package (0x0A)
                            {
                                0x1B58, 
                                0x0FA0, 
                                One, 
                                Zero, 
                                Zero, 
                                0x03, 
                                0x50, 
                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                "Cluster0.CL5"
                            }
                        })
                    }
                }

                Device (CPU0)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, Zero)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x05)  // trace _STA SYSM/CLS0/CPU0
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }

                Device (CPU1)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, One)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x06)  // trace _STA SYSM/CLS0/CPU1
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }

                Device (CPU2)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x02)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x07)  // trace _STA SYSM/CLS0/CPU2
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }
            }

            Device (CLS1)
            {
                Name (_HID, "ACPI0010" /* Processor Container Device */)  // _HID: Hardware ID
                Name (_UID, One)  // _UID: Unique ID
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                DBGL (0x08)  // trace _STA SYSM/CLS1
                    Return (0x0F)
                }

                Method (_LPI, 0, NotSerialized)  // _LPI: Low Power Idle States
                {
                DBGL (0x09)  // trace _LPI SYSM/CLS1
                    If (PEPI)
                    {
                        Return (Package (0x05)
                        {
                            Zero, 
                            0x01000000, 
                            0x02, 
                            Package (0x0A)
                            {
                                0x09C4, 
                                0x01F4, 
                                One, 
                                Zero, 
                                Zero, 
                                Zero, 
                                0x40, 
                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                "Cluster0.CL4"
                            }, 

                            Package (0x0A)
                            {
                                0x1B58, 
                                0x0FA0, 
                                One, 
                                Zero, 
                                Zero, 
                                0x03, 
                                0x50, 
                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                ResourceTemplate ()
                                {
                                    Register (SystemMemory, 
                                        0x00,               // Bit Width
                                        0x00,               // Bit Offset
                                        0x0000000000000000, // Address
                                        ,)
                                }, 

                                "Cluster0.CL5"
                            }
                        })
                    }
                }

                Device (CPU0)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x03)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x0A)  // trace _STA SYSM/CLS1/CPU0
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }

                Device (CPU1)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x04)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x0B)  // trace _STA SYSM/CLS1/CPU1
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }

                Device (CPU2)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x05)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x0C)  // trace _STA SYSM/CLS1/CPU2
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }

                Device (CPU3)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x06)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x0D)  // trace _STA SYSM/CLS1/CPU3
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }
            }

            Device (CLS2)
            {
                Name (_HID, "ACPI0010" /* Processor Container Device */)  // _HID: Hardware ID
                Name (_UID, 0x02)  // _UID: Unique ID
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                DBGL (0x0E)  // trace _STA SYSM/CLS2
                    Return (0x0F)
                }

                Device (CPU0)
                {
                    Name (_HID, "ACPI0007" /* Processor Device */)  // _HID: Hardware ID
                    Name (_UID, 0x07)  // _UID: Unique ID
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                DBGL (0x0F)  // trace _STA SYSM/CLS2/CPU0
                        Return (0x0F)
                    }

                    Name (_LPI, Package (0x05)  // _LPI: Low Power Idle States
                    {
                        Zero, 
                        Zero, 
                        0x02, 
                        Package (0x0A)
                        {
                            Zero, 
                            Zero, 
                            One, 
                            Zero, 
                            Zero, 
                            Zero, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C1"
                        }, 

                        Package (0x0A)
                        {
                            0x0258, 
                            0x01F4, 
                            One, 
                            Zero, 
                            Zero, 
                            0x02, 
                            ResourceTemplate ()
                            {
                                Register (FFixedHW, 
                                    0x20,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x00000000FFFFFFFF, // Address
                                    0x03,               // Access Size
                                    )
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            ResourceTemplate ()
                            {
                                Register (SystemMemory, 
                                    0x00,               // Bit Width
                                    0x00,               // Bit Offset
                                    0x0000000000000000, // Address
                                    ,)
                            }, 

                            "NCC.C4"
                        }
                    })
                }
            }
        }

        Device (UFS0)
        {
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                DBGL (0x10)  // trace _STA UFS0
                UFSS ()
                Return (0x0F)
            }

            Name (_HID, "QCOM24A5")  // _HID: Hardware ID
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_CCA, Zero)  // _CCA: Cache Coherency Attribute
            Method (_CRS, 0, NotSerialized)  // _CRS: Current Resource Settings
            {
                DBGL (0x11)  // trace _CRS UFS0
                Name (RBUF, ResourceTemplate ()
                {
                    Memory32Fixed (ReadWrite,
                        0x01D84000,         // Address Base
                        0x00015000,         // Address Length
                        )
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Exclusive, ,, )
                    {
                        0x00000129,
                    }
                })
                Return (RBUF) /* \_SB_.UFS0._CRS.RBUF */
            }

            Device (DEV0)
            {
                Method (_ADR, 0, NotSerialized)  // _ADR: Address
                {
                    Return (0x08)
                }

                Method (_RMV, 0, NotSerialized)  // _RMV: Removal Status
                {
                    Return (Zero)
                }
            }
        }

        Name (QUFN, Zero)
        Name (DPP0, Buffer (One)
        {
             0x00                                             // .
        })
        Name (DPP1, Buffer (One)
        {
             0x00                                             // .
        })
        Name (MPP0, Buffer (One)
        {
             0x00                                             // .
        })
        Name (MPP1, Buffer (One)
        {
             0x00                                             // .
        })
        Name (HPDB, Zero)
        Name (HPDS, Buffer (One)
        {
             0x00                                             // .
        })
        Name (PINA, Zero)
        Name (DPPN, 0x0D)
        Name (CCST, Buffer (One)
        {
             0x02                                             // .
        })
        Name (PORT, Buffer (One)
        {
             0x02                                             // .
        })
        Name (HIRQ, Buffer (One)
        {
             0x00                                             // .
        })
        Name (HSFL, Buffer (One)
        {
             0x00                                             // .
        })
        Name (USBC, Buffer (One)
        {
             0x0B                                             // .
        })
        Name (MUXC, Buffer (One)
        {
             0x00                                             // .
        })
        Device (UUPC)
        {
            Name (_HID, EisaId ("PNP0A05") /* Generic Container Device */)  // _HID: Hardware ID
            Name (_UID, "USB _UPC Object Container")  // _UID: Unique ID
            Name (UPCC, Package (0x04)
            {
                One, 
                0x09, 
                Zero, 
                Zero
            })
            Name (UPC2, Package (0x04)
            {
                One, 
                Zero, 
                Zero, 
                Zero
            })
            Name (UPC3, Package (0x04)
            {
                One, 
                0x03, 
                Zero, 
                Zero
            })
            Name (UPCN, Package (0x04)
            {
                Zero, 
                0xFF, 
                Zero, 
                Zero
            })
        }

        Device (URS0)
        {
            Name (_HID, "QCOM0C8B")  // _HID: Hardware ID
            Name (_CID, Package (0x02)  // _CID: Compatible ID
            {
                "PNP0CA1", 
                "QCOMFFE1"
            })
            Alias (PSUB, _SUB)
            Name (_UID, Zero)  // _UID: Unique ID
            Name (_CCA, Zero)  // _CCA: Cache Coherency Attribute
            Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
            {
                Memory32Fixed (ReadWrite,
                    0x0A600000,         // Address Base
                    0x000FFFFF,         // Address Length
                    )
            })
            Device (USB0)
            {
                Name (_ADR, Zero)  // _ADR: Address
                Name (_S0W, 0x03)  // _S0W: S0 Device Wake State
                Name (_PLD, Package (0x01)  // _PLD: Physical Location of Device
                {
                    ToPLD (
                        PLD_Revision           = 0x2,
                        PLD_IgnoreColor        = 0x1,
                        PLD_Red                = 0x0,
                        PLD_Green              = 0x0,
                        PLD_Blue               = 0x0,
                        PLD_Width              = 0x0,
                        PLD_Height             = 0x0,
                        PLD_UserVisible        = 0x1,
                        PLD_Dock               = 0x0,
                        PLD_Lid                = 0x0,
                        PLD_Panel              = "BACK",
                        PLD_VerticalPosition   = "CENTER",
                        PLD_HorizontalPosition = "LEFT",
                        PLD_Shape              = "VERTICALRECTANGLE",
                        PLD_GroupOrientation   = 0x0,
                        PLD_GroupToken         = 0x0,
                        PLD_GroupPosition      = 0x0,
                        PLD_Bay                = 0x0,
                        PLD_Ejectable          = 0x0,
                        PLD_EjectRequired      = 0x0,
                        PLD_CabinetNumber      = 0x0,
                        PLD_CardCageNumber     = 0x0,
                        PLD_Reference          = 0x0,
                        PLD_Rotation           = 0x0,
                        PLD_Order              = 0x0,
                        PLD_VerticalOffset     = 0xFFFF,
                        PLD_HorizontalOffset   = 0xFFFF)

                })
                Method (_UPC, 0, NotSerialized)  // _UPC: USB Port Capabilities
                {
                    Return (^^^UUPC.UPCC) /* \_SB_.UUPC.UPCC */
                }

                Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                {
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Shared, ,, )
                    {
                        0x000000A5,
                    }
                    Interrupt (ResourceConsumer, Level, ActiveHigh, SharedAndWake, ,, )
                    {
                        0x000000A3,
                    }
                    Interrupt (ResourceConsumer, Level, ActiveHigh, SharedAndWake, ,, )
                    {
                        0x00000211,
                    }
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, SharedAndWake, ,, )
                    {
                        0x0000020F,
                    }
                    Interrupt (ResourceConsumer, Edge, ActiveHigh, SharedAndWake, ,, )
                    {
                        0x0000020E,
                    }
                })
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                DBGL (0x12)  // trace _STA URS0/USB0
                UFSS ()
                    Return (0x0F)
                }

                Method (DPM0, 1, NotSerialized)
                {
                    DPP0 = Arg0
                }

                Method (CCVL, 0, NotSerialized)
                {
                    Return (CCST) /* \_SB_.CCST */
                }

                Method (HSEN, 0, NotSerialized)
                {
                    Return (HSFL) /* \_SB_.HSFL */
                }

                Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
                {
                DBGL (0x13)  // trace _DSM URS0/USB0
                    Switch (ToBuffer (Arg0))
                    {
                        Case (ToUUID ("ce2ee385-00e6-48cb-9f05-2edb927c4899") /* USB Controller */){                            Switch (ToInteger (Arg2))
                            {
                                Case (Zero)
                                {
                                    Switch (ToInteger (Arg1))
                                    {
                                        Case (Zero)
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x1D                                             // .
                                            })
                                            Break
                                        }
                                        Default
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x01                                             // .
                                            })
                                            Break
                                        }

                                    }

                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }
                                Case (0x02)
                                {
                                    Return (Zero)
                                    Break
                                }
                                Case (0x03)
                                {
                                    Return (Zero)
                                    Break
                                }
                                Case (0x04)
                                {
                                    Return (0x02)
                                    Break
                                }
                                Default
                                {
                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }

                            }
                        }
                        Default
                        {
                            Return (Buffer (One)
                            {
                                 0x00                                             // .
                            })
                            Break
                        }

                    }
                }

                Method (PHYC, 0, NotSerialized)
                {
                    Name (CFG0, Package (0x00){})
                    Return (CFG0) /* \_SB_.URS0.USB0.PHYC.CFG0 */
                }
            }

            Device (UFN0)
            {
                Name (_ADR, One)  // _ADR: Address
                Name (_S0W, 0x03)  // _S0W: S0 Device Wake State
                Name (_PLD, Package (0x01)  // _PLD: Physical Location of Device
                {
                    ToPLD (
                        PLD_Revision           = 0x2,
                        PLD_IgnoreColor        = 0x1,
                        PLD_Red                = 0x0,
                        PLD_Green              = 0x0,
                        PLD_Blue               = 0x0,
                        PLD_Width              = 0x0,
                        PLD_Height             = 0x0,
                        PLD_UserVisible        = 0x1,
                        PLD_Dock               = 0x0,
                        PLD_Lid                = 0x0,
                        PLD_Panel              = "BACK",
                        PLD_VerticalPosition   = "CENTER",
                        PLD_HorizontalPosition = "LEFT",
                        PLD_Shape              = "VERTICALRECTANGLE",
                        PLD_GroupOrientation   = 0x0,
                        PLD_GroupToken         = 0x0,
                        PLD_GroupPosition      = 0x0,
                        PLD_Bay                = 0x0,
                        PLD_Ejectable          = 0x0,
                        PLD_EjectRequired      = 0x0,
                        PLD_CabinetNumber      = 0x0,
                        PLD_CardCageNumber     = 0x0,
                        PLD_Reference          = 0x0,
                        PLD_Rotation           = 0x0,
                        PLD_Order              = 0x0,
                        PLD_VerticalOffset     = 0xFFFF,
                        PLD_HorizontalOffset   = 0xFFFF)

                })
                Method (_UPC, 0, NotSerialized)  // _UPC: USB Port Capabilities
                {
                    Return (^^^UUPC.UPCC) /* \_SB_.UUPC.UPCC */
                }

                Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
                {
                    Interrupt (ResourceConsumer, Level, ActiveHigh, Shared, ,, )
                    {
                        0x000000A5,
                    }
                    Interrupt (ResourceConsumer, Level, ActiveHigh, SharedAndWake, ,, )
                    {
                        0x000000A3,
                    }
                })
                Method (CCVL, 0, NotSerialized)
                {
                    Return (CCST) /* \_SB_.CCST */
                }

                Method (_DSM, 4, Serialized)  // _DSM: Device-Specific Method
                {
                DBGL (0x14)  // trace _DSM URS0/UFN0
                    Switch (ToBuffer (Arg0))
                    {
                        Case (ToUUID ("fe56cfeb-49d5-4378-a8a2-2978dbe54ad2") /* Unknown UUID */){                            Switch (ToInteger (Arg2))
                            {
                                Case (Zero)
                                {
                                    Switch (ToInteger (Arg1))
                                    {
                                        Case (Zero)
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x03                                             // .
                                            })
                                            Break
                                        }
                                        Default
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x01                                             // .
                                            })
                                            Break
                                        }

                                    }

                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }
                                Case (One)
                                {
                                    Return (0x20)
                                    Break
                                }
                                Default
                                {
                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }

                            }
                        }
                        Case (ToUUID ("18de299f-9476-4fc9-b43b-8aeb713ed751") /* Unknown UUID */){                            Switch (ToInteger (Arg2))
                            {
                                Case (Zero)
                                {
                                    Switch (ToInteger (Arg1))
                                    {
                                        Case (Zero)
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x03                                             // .
                                            })
                                            Break
                                        }
                                        Default
                                        {
                                            Return (Buffer (One)
                                            {
                                                 0x01                                             // .
                                            })
                                            Break
                                        }

                                    }

                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }
                                Case (One)
                                {
                                    Return (0x39)
                                    Break
                                }
                                Default
                                {
                                    Return (Buffer (One)
                                    {
                                         0x00                                             // .
                                    })
                                    Break
                                }

                            }
                        }
                        Default
                        {
                            Return (Buffer (One)
                            {
                                 0x00                                             // .
                            })
                            Break
                        }

                    }
                }

                Method (PHYC, 0, NotSerialized)
                {
                    Name (CFG0, Package (0x00){})
                    Return (CFG0) /* \_SB_.URS0.UFN0.PHYC.CFG0 */
                }
            }
        }
    }

    Scope (\_TZ)
    {
        ThermalZone (TZCP)   // CPU
        {
            Name (_TZP, 100)    // poll every 10 s
            Name (_CRT, 3832)
            Method (_TMP, 0, NotSerialized)
            {
                Local1 = Zero
                Local0 = \_SB.TCNV (\_SB.T0S1)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S2)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S3)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S4)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S5)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S6)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S7)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S8)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0S9)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0SA)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0SB)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0SC)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0SD)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T0SE)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S1)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S2)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S3)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S4)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S5)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                If (Local1 == Zero)
                {
                    Local1 = 2982       // no valid sample: 25 C
                }

                Return (Local1)
            }
        }

        ThermalZone (TZGP)   // GPU
        {
            Name (_TZP, 100)    // poll every 10 s
            Name (_CRT, 3832)
            Method (_TMP, 0, NotSerialized)
            {
                Local1 = Zero
                Local0 = \_SB.TCNV (\_SB.T2S1)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S2)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S3)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S4)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S5)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S6)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S7)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S8)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                If (Local1 == Zero)
                {
                    Local1 = 2982       // no valid sample: 25 C
                }

                Return (Local1)
            }
        }

        ThermalZone (TZPL)   // PLATFORM
        {
            Name (_TZP, 100)    // poll every 10 s
            Name (_CRT, 3732)
            Method (_TMP, 0, NotSerialized)
            {
                Local1 = Zero
                Local0 = \_SB.TCNV (\_SB.T0S0)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S0)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S6)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S7)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S8)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1S9)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SA)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SB)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SC)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SD)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SE)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T1SF)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S0)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2S9)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2SA)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2SB)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                Local0 = \_SB.TCNV (\_SB.T2SC)
                If (Local0 > Local1)
                {
                    Local1 = Local0
                }

                If (Local1 == Zero)
                {
                    Local1 = 2982       // no valid sample: 25 C
                }

                Return (Local1)
            }
        }

    }
}
