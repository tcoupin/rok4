#Récupère le nom du projet parent
SET(PARENT_PROJECT_NAME ${PROJECT_NAME})

#Défini le nom du projet 
project(pyramide)

#définit la version du projet : 1.0.0 MAJOR.MINOR.PATCH
list(GET BE4_VERSION 0 CPACK_PACKAGE_VERSION_MAJOR)
list(GET BE4_VERSION 1 CPACK_PACKAGE_VERSION_MINOR)
list(GET BE4_VERSION 2 CPACK_PACKAGE_VERSION_PATCH)

cmake_minimum_required(VERSION 2.6)

########################################
#Attention aux chemins
set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../cmake/Modules ${CMAKE_MODULE_PATH})

if(NOT DEFINED DEP_PATH)
  set(DEP_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../target)
endif(NOT DEFINED DEP_PATH)

if(NOT DEFINED ROK4LIBSDIR)
  set(ROK4LIBSDIR ${CMAKE_CURRENT_SOURCE_DIR}/../../lib)
endif(NOT DEFINED ROK4LIBSDIR)

set(BUILD_SHARED_LIBS OFF)


#Build Type si les build types par défaut de CMake ne conviennent pas
#set(CMAKE_BUILD_TYPE specificbuild)
#set(CMAKE_CXX_FLAGS_SPECIFICBUILD "-g -O0 -msse -msse2 -msse3")
#set(CMAKE_C_FLAGS_SPECIFICBUILD "")


########################################
#définition des fichiers sources

#add_executable(${PROJECT_NAME} ${${PROJECT_NAME}_SRCS})

########################################
#Définition des dépendances.
include(ROK4Dependencies)

set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES ${CMAKE_CURRENT_BINARY_DIR}/src/makefile)

set(DEP_INCLUDE_DIR ${TIFF_INCLUDE_DIR} )

set(VERSION_TEXT ${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH})
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/Makefile.PL.in ${CMAKE_CURRENT_BINARY_DIR}/src/Makefile.PL @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/bin/be4.pl.in ${CMAKE_CURRENT_BINARY_DIR}/src/bin/be4.pl @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/bin/joinCache.pl.in ${CMAKE_CURRENT_BINARY_DIR}/src/bin/joinCache.pl @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/bin/create-layer.pl.in ${CMAKE_CURRENT_BINARY_DIR}/src/bin/create-layer.pl @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/bin/coord2image.pl.in ${CMAKE_CURRENT_BINARY_DIR}/src/bin/coord2image.pl @ONLY)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/bin/be4-simulator.pl.in ${CMAKE_CURRENT_BINARY_DIR}/src/bin/be4-simulator.pl @ONLY)

set(ENV{CFLAGS} "-O3")
add_custom_command(OUTPUT src/makefile COMMAND mkdir -p src COMMAND cp -f -r -l ${CMAKE_CURRENT_SOURCE_DIR}/* src)
add_custom_command(OUTPUT install_be4 COMMAND BE4_ENV="${CMAKE_CURRENT_BINARY_DIR}/install" make -f makefile COMMAND BE4_ENV="${CMAKE_CURRENT_BINARY_DIR}/install" make -f makefile install DEPENDS src/makefile WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/src)

add_custom_target(be4-build ALL DEPENDS install_be4)

include_directories(${CMAKE_CURRENT_BINARY_DIR} ${DEP_INCLUDE_DIR})

########################################

# Gestion des tests unitaires (PerlUnit)
# Les fichiers tests doivent être dans le répertoire ../tests/perlunit
# Les fichiers tests doivent être nommés PerlUnitCLASSE_TESTEE.t
# le lanceur de test doit être dans le répertoire ../tests/perlunit
# L'éxecutable "UnitTester-Nom_Projet" sera généré pour lancer tous les tests
# Activé uniquement si la variable UNITTEST est vraie

if(UNITTEST)
    include_directories(${CMAKE_CURRENT_BINARY_DIR} ${DEP_INCLUDE_DIR} ${CMAKE_CURRENT_SOURCE_DIR} ${CPPUNIT_INCLUDE_DIR})
    ENABLE_TESTING()
    add_definitions(-DUNITTEST)

    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/perlunit)
        # Exécution des tests unitaires PerlUnit
        FILE(GLOB UnitTests_SRCS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "tests/perlunit/BE4/PerlUnit*.t")
        
        FOREACH(test ${UnitTests_SRCS})
            MESSAGE("  - adding test ${test}")
            GET_FILENAME_COMPONENT(TestName ${test} NAME_WE)
            ADD_TEST(NAME "BE4::${TestName}" COMMAND perl -I ${CMAKE_CURRENT_BINARY_DIR}/install/lib/perl5 ${CMAKE_CURRENT_BINARY_DIR}/src/${test})
        ENDFOREACH(test)

        FILE(GLOB UnitTests_SRCS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "tests/perlunit/JOINCACHE/PerlUnit*.t")

        FOREACH(test ${UnitTests_SRCS})
            MESSAGE("  - adding test ${test}")
            GET_FILENAME_COMPONENT(TestName ${test} NAME_WE)
            ADD_TEST(NAME "JOINCACHE::${TestName}" COMMAND perl -I ${CMAKE_CURRENT_BINARY_DIR}/install/lib/perl5 ${CMAKE_CURRENT_BINARY_DIR}/src/${test})
        ENDFOREACH(test)

        # Nettoyage du dossier temporaire
        MESSAGE("  - adding cleaning")
        ADD_TEST(NAME "Cleaning" COMMAND rm -rf ${CMAKE_CURRENT_BINARY_DIR}/src/tests/temp)

    endif(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/tests/perlunit)
  
endif(UNITTEST)

########################################
#Documentation NaturalDocs
#Utilisation du fichier 
if(BUILD_DOC)
    find_package(NaturalDocs)
    if(NATURALDOCS_FOUND)
        add_custom_target(doc ALL BE4_SRC="${CMAKE_CURRENT_SOURCE_DIR}" make doc WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/src COMMENT "Generating BE4 documentation with NaturalDocs" VERBATIM )
        #add_custom_target(doc ALL make doc WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/src COMMENT "Generating BE4 documentation with NaturalDocs" VERBATIM )
        INSTALL(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/src/docs/" DESTINATION share/doc/${PARENT_PROJECT_NAME}/${PROJECT_NAME})
    endif(NATURALDOCS_FOUND)

endif(BUILD_DOC)

#Installe la documentation de base
INSTALL(FILES QUESTIONS README CHANGES INSTALL FIXME DESTINATION share/doc/${PARENT_PROJECT_NAME}/${PROJECT_NAME})

########################################
#Installation dans les répertoires par défauts
#Pour installer dans le répertoire /opt/projet :
#cmake -DCMAKE_INSTALL_PREFIX=/opt/projet 


#Installe les différents fichers nécessaires
INSTALL(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/install/" DESTINATION . USE_SOURCE_PERMISSIONS)

########################################
# Paramétrage de la gestion de package CPack
# Génère un fichier PROJET-VERSION-OS-32/64bit.tar.gz 

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  SET(BUILD_ARCHITECTURE "64bit")
else()
  SET(BUILD_ARCHITECTURE "32bit")
endif()
SET(CPACK_SYSTEM_NAME "${CMAKE_SYSTEM_NAME}-${BUILD_ARCHITECTURE}")
INCLUDE(CPack)
