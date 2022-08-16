# This file contains common settings, flags, and variables for
# my FFXIV EXD/CSV conversion scripts. Feel free to change
# them however you see fit. These settings are applied every
# time you get back into main script screen.


# The name of project directory. It's going to be created inside
# current script directory and will overall contain the following
# structure:
# (Weblate)
# └───<project_directory_name>
#     ├───csv                 - CSV files
#     ├───exd_mod_<lang_code> - Modded EXD files for <language_code>
#     ├───exd_source          - Source EXD files
#     ├───exh_mod_<lang_code> - Modded EXH files for <language_code>
#     └───exh_source          - Source EXH files
#
# (Standard)
# └───<project_directory_name>
#     ├───csv        - CSV files
#     ├───exd_mod    - Modded EXD files
#     ├───exd_source - Source EXD files
#     ├───exh_mod    - Modded EXH files
#     └───exh_source - Source EXH files
$CURRENT_DIR = 'current'

# Should the scripts print out more info about what's going on?
#
# Note: Turning this off might improve performance.
$VERBOSE_OUTPUT = $true

# What string should be used as a column separator?
#
# Note: After changing this you'll have to re-convert everything
# from EXD to CSV.
$COLUMN_SEPARATOR = '<tab>'

# During update:
# In which files the update script should add index at the start of
# the updated strings?
#
# E.g. Old translation string = "String A"
#      New translation string = "9B_String B" where 9 is index (0x0000009B)
$UPDATE_ADD_INDEX = @(
    'addon', 'lobby', 'error'
)

# Use new line character instead of <br> tag
# When $true:
#   This is an example line
#   with a line break.
# When $false:
#   This is an example line<br>with a line break.
# 
# Note: CSVtoEXD script will not care about this option and convert both NL and
#       <br> into the same line break variable.
#
# WARNING! During update, if your current CSVs don't have <br> and the new ones
#          do (or vice versa), the update script will count that as a change
#          between game patches which would not be accurate and is probably
#          undesirable.
$USE_NL_BYTE = $true

# What quest files should be included or excluded. Only one list can be active
# at a time. The quest files are considered to be files in folders:
#   exd/cut_scene
#   exd/opening
#   exd/quest
# If $QUEST_INCLUDE_LIST is filled, the script will convert only files listed in
# this list.
# If $QUEST_EXCLUDE_LIST is filled, the script will skip the files listed in this
# list.
# If none of those lists are filled, the script will convert everything.
# If both of those lists are filled, the script will error out.
# Each entry in the list should be an EXH file name w/o '.exh', e.g. 'jobdrg300_01067'
$QUEST_INCLUDE_LIST = @(
    <#

    # 2.0 - A Realm Reborn
    #  Opening cutscene + Gridania
    'manfst000_00083',
    #   Gridania
    'manfst050_00540', 'openinggridania', 'manfst001_00039', 'manfst002_00085',
    'manfst003_00123', 'manfst004_00124', 'subfst010_00001', 'subfst005_00028',
    'subfst045_00201', 'manfst005_00445', 'subfst034_00128', 'xxafst034_03854',
    'subfst038_00175', 'subfst038_00175', 'xxafst031_03855', 'subfst035_00129',
    'subfst027_00176', 'subfst049_00376', 'subfst056_00377', 'subfst058_00379',
    'subfst059_00380', 'subfst060_00381', 'subfst068_00384', 'subfst073_00387',
    'subfst055_00161', 'manfst006_00446', 'manfst007_00447', 'manfst008_00448',
    'manfst009_00449', 'manfst200_00507', 'subwil141_00674',
    #    Limsa
    'mansea000_00541', 'mansea050_00542', 'openinglimsalominsa', 'mansea001_00107',
    'mansea002_00108', 'mansea003_00109', 'subsea001_00111', 'subsea050_00462',
    'subsea051_00463', 'mansea005_00543', 'subsea053_00465', 'subsea054_00466',
    'subsea055_00467', 'subsea056_00468', 'subsea057_00469', 'subsea100_00397',
    'subsea105_00402', 'subsea106_00403', 'subsea109_00406', 'subsea115_00412',
    'subsea118_00415', 'subsea116_00413', 'subsea117_00414', 'mansea006_00689',
    'mansea007_00544', 'mansea008_00690', 'mansea009_00545', 'mansea200_00546',
    #    Ul'dah
    'manwil000_00548', 'manwil050_00549', 'openinguldah', 'manwil001_00594',
    'manwil002_00568', 'manwil003_00569', 'manwil004_00570', 'subwil027_00595',
    'subwil025_00671', 'manwil005_00550', 'subwil060_00303', 'xxawil063_03852',
    'subwil064_00307', 'subwil066_00320', 'subwil026_00623', 'subwil080_00328',
    'subwil095_00503', 'subwil081_00329', 'subwil082_00330', 'xxawil083_03853',
    'subwil084_00332', 'subwil085_00333', 'subwil086_00334', 'subwil088_00336',
    'manwil006_00628', 'manwil007_00551', 'manwil008_00641', 'manwil009_00552',
    'manwil200_00528', 'subfst102_00673',
    #   Ifrit arc
    'manfst203_00675', 'mansea203_00245', 'subsea150_00676', 'manfst204_00677',
    'subfst103_00678', 'manfst205_00660', 'manfst206_00509', 'manfst207_00510',
    'subwil110_00618', 'subwil111_00619', 'subwil112_00620', 'subwil113_00621',
    'subwil114_00622', 'subwil129_00574', 'manfst208_00272', 'manfst209_00343',
    'manfst300_00511',
    #   GC Choice
    #    Twin Adder
    'manfst302_00680', 'manfst303_00683', 'subfst120_00700',
    #    Maelstrom
    'mansea302_00681', 'mansea303_00684', 'subsea910_00701',
    #    Immortal Flames
    'manwil302_00682', 'manwil303_00685', 'subwil160_00702',
    #   Sylph arc
    'manfst304_00513', 'xxausa002_03856', 'gaiusa003_00709', 'gaiusa004_00710',
    'gaiusa101_00715', 'xxausa103_03857', 'xxausa104_03858', 'gaiusa105_00719',
    'gaiusa201_00724', 'gaiusa202_00725', 'xxausa203_03859', 'xxausa301_03860',
    'xxausa302_03861', 'gaiusa305_00737', 'gaiusa306_00738', 'gaiusa308_00740',
    'xxausa308_03862', 'manfst306_00514', 'gaiusa401_00743', 'gaiusa402_00744',
    'gaiusa404_00746',
    #   Lahabrea arc
    'gaiusa405_00747', 'gaiusa404_00746', 'gaiusa406_00748', 'gaiusa504_00756',
    'gaiusa510_00762', 'gaiusa601_00763', 'gaiusa603_00765', 'gaiusa701_00774',
    'gaiusa702_00775', 'gaiusa703_00776', 'gaiusa704_00777', 'gaiusa705_00778',
    'gaiusa709_00782', 'gaiusa710_00783', 'xxausa711_03863', 'xxausa801_03864',
    'gaiusa803_00787', 'gaiusa802_00786', 'gaiusa904_00799', 'gaiusa905_00800',
    'gaiusa906_00801'
    #   Titan arc
    'manfst309_00516', 'gaiusb002_00809', 'gaiusb003_00810', 'gaiusb004_00811',
    'gaiusb005_00812', 'gaiusb007_00814', 'xxausb012_03865', 'gaiusb102_00821',
    'gaiusb103_00822', 'gaiusb112_00831', 'gaiusb201_00832', 'xxausb208_03866',
    'gaiusb209_00840', 'gaiusb212_00843', 'gaiusb304_00845', 'gaiusb305_00846',
    'gaiusb307_00848', 'gaiusb309_00850', 'gaiusb314_00855', 'gaiusb315_00856',
    'gaiusb401_00857'
    #   Garuda arc
    'manfst313_00517', 'xxausb503_03867', 'gaiusb507_00876', 'gaiusb509_00878',
    'manfst401_00518', 'gaiusb601_00883', 'gaiusb602_00884', 'gaiusb604_00886',
    'gaiusb605_00887', 'gaiusb607_00889', 'gaiusb608_00890', 'gaiusb702_00897',
    'gaiusb801_00910', 'gaiusb802_00911', 'gaiusb803_00912', 'xxausb808_03868',
    'gaiusb901_00924', 'gaiusb904_00927', 'xxausb914_03869', 'gaiusc001_00938',
    'gaiusc002_00939', 'gaiusc003_00940', 'gaiusc004_00941', 'gaiusc101_00952',
    'gaiusc102_00953', 'gaiusc104_00955', 'gaiusc105_00956', 'gaiusc108_00959',
    'gaiusc201_00960', 'gaiusc202_00961', 'gaiusc203_00962', 'gaiusc204_00963',
    'gaiusc208_00967', 'xxausc307_03870', 'gaiusc308_00975', 'manfst404_00519',
    'manfst405_00520'
    #   Gaius arc + Finale
    'gaiusc403_00978', 'gaiusc405_00980', 'gaiusc406_00981', 'gaiusc407_00982',
    'gaiusc408_00983', 'gaiusc409_00984', 'gaiusc411_00986', 'gaiusc601_01001',
    'gaiusc602_01002', 'xxausc603_03871', 'gaiusc604_01004', 'gaiusc605_01005',
    'manfst407_00521', 'manfst408_00522', 'gaiusc901_01036', 'xxcusc901_04521',
    'gaiusc902_01037', 'xxausc908_03872', 'manfst502_01136', 'xxafst502_03873',
    'manfst503_00524', 'xxcfst503_04522', 'manfst600_00525'
    #  2.1

    #  2.2

    #  2.3

    #  2.4
    
    #  2.5
    
    #  2.58

    # 3.0 - Heavensward


    # Class/Job quests
    #  - GLD
    'clsgla011_00285', 'clsgla020_00253', 'clsgla001_00177',
    #  - PGL
    'clspgl011_00532', 'clspgl020_00533', 'clspgl001_00178',
    #  - MRD
    'clsexc011_00310', 'clsexc020_00311', 'clsexc001_00179',
    #  - LNC
    'clslnc998_00132', 'clslnc000_00023', 'clslnc999_00180',
    #  - DRG
    'jobdrg300_01067', 'jobdrg350_01068', 'jobdrg400_01069', 'jobdrg450_01070',
    'jobdrg451_01071', 'jobdrg500_01072'
    #  - ARC
    'clsarc998_00131', 'clsarc000_00021', 'clsarc999_00181', 'clsarc100_00219',
    'clsarc001_00046', 'clsarc002_00067', 'clsarc997_00134', 'clsarc003_00068',
    'clsarc004_00070', 'clsarc005_00071', 'clsarc006_00076',
    #  - CNJ
    'clscnj998_00133', 'clscnj000_00022', 'clscnj999_00182',
    #  - THM
    'clsthm011_00344', 'clsthm020_00345', 'clsthm001_00183',
    #  - ACN
    'clsacn011_00452', 'clsacn020_00453', 'clsacn001_00451',
    #  - ROG
    'clsexc001_00179',
    #  - DRK
    'jobdrk299_02110', 'jobdrk300_02053', 'jobdrk301_02054', 'jobdrk350_02055',
    'jobdrk400_02056', 'jobdrk450_02057', 'jobdrk500_02058',

    #  - BLU
    'jobaoz001_03192', 'jobaoz010_03193', 'jobaoz100_03194', 'jobaoz200_03195',
    'jobaoz300_03196', 'jobaoz400_03197', 'jobaoz500_03198', 'jobaoz501_03199',

    # Seasonal Events
    'fesevn101_02206', 'fespdy701_04471', 'fespdy702_04472', 'fesest801_04590',
    'fesgsc601_04584', 
    #  - Moonfire Faire 2022
    'fessum801_04540', 'fessum802_04541'

    #>
)
$QUEST_EXCLUDE_LIST = @()



# The following options are exclusive for Weblate version and have no effect
# on standard version.

# In what quest files should index be added at the start of the string?
# This was made by request of one of the translators. The quests from this
# list will get a decimal number at the startof the strings which would allow
# translators to go directly to the string with this number in the quest file.
$QUEST_ADD_INDEX_LIST = @(
    <#
    
    #    Ul'dah
    'manwil000_00548', 'manwil050_00549', 'openinguldah', 'manwil001_00594',
    'manwil002_00568', 'manwil003_00569', 'manwil004_00570', 'subwil027_00595',
    'subwil025_00671', 'manwil005_00550', 'subwil060_00303', 'xxawil063_03852',
    'subwil064_00307', 'subwil066_00320', 'subwil026_00623', 'subwil080_00328',
    'subwil095_00503', 'subwil081_00329', 'subwil082_00330', 'xxawil083_03853',
    'subwil084_00332', 'subwil085_00333', 'subwil086_00334', 'subwil088_00336',
    'manwil006_00628', 'manwil007_00551', 'manwil008_00641', 'manwil009_00552',
    'manwil200_00528', 'subfst102_00673',
    #   Ifrit arc
    'manfst203_00675', 'mansea203_00245', 'subsea150_00676', 'manfst204_00677',
    'subfst103_00678', 'manfst205_00660', 'manfst206_00509', 'manfst207_00510',
    'subwil110_00618', 'subwil111_00619', 'subwil112_00620', 'subwil113_00621',
    'subwil114_00622', 'subwil129_00574', 'manfst208_00272', 'manfst209_00343',
    'manfst300_00511',
    
    #   Sylph arc
    'manfst304_00513', 'xxausa002_03856', 'gaiusa003_00709', 'gaiusa004_00710',
    'gaiusa101_00715', 'xxausa103_03857', 'xxausa104_03858', 'gaiusa105_00719',
    'gaiusa201_00724', 'gaiusa202_00725', 'xxausa203_03859', 'xxausa301_03860',
    'xxausa302_03861', 'gaiusa305_00737', 'gaiusa306_00738', 'gaiusa308_00740',
    'xxausa308_03862', 'manfst306_00514', 'gaiusa401_00743', 'gaiusa402_00744',
    'gaiusa404_00746'

    #>
)

# The list of FFXIV's official languages. Any language that
# is not on this list is considered unofficial.
$OFFICIAL_LANGUAGES = @( 'chs', 'cht', 'de', 'en', 'fr', 'ja', 'ko' )

# What language should be assumed if input file doesn't have
# a language code in its name?
$DEFAULT_LANGUAGE_CODE = 'ru'

# I define 'sublanguage' as a language that is based on another so-called
# 'parent' language, which can be both official, and unofficial. E.g. in
# Russian we have 'Russian-English language' where the game terms, NPC names,
# location names, etc. are kept in English. This is useful on the first stages
# of translation since people would be able to use your translation w/o
# sacrificing communication with other people.
# Benefits:
#  * If sublanguage string is empty, the script will take string with the
#    same ID/index from parent language
#  * As such it removes the hassle of keeping sublanguage file up to date
#    with its parent
#  * Since you're only keeping strings that are required to be changed in
#    parent language, overall files' size for the sublanguage is much lower
# The format for every entry is:
#    <sublanguage_code> = '<parent_language_code>'
# Note: Language codes can be artificial. The scripts won't care as long as
#       there are necessary files/directories with that language code.
$SUBLANGUAGES = @{
    ruen = 'ru'
}
