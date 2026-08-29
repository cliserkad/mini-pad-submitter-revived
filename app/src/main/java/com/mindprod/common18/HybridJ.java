/*
 * [HybridJ.java]
 *
 * Summary: Converts a JApplet into an Application.
 *
 * Copyright: (c) 2005-2017 Roedy Green, Canadian Mind Products, http://mindprod.com
 *
 * Licence: This software may be copied and used freely for any purpose but military.
 *          http://mindprod.com/contact/nonmil.html
 *
 * Requires: JDK 1.8+
 *
 * Created with: JetBrains IntelliJ IDEA IDE http://www.jetbrains.com/idea/
 *
 * Version History:
 *  1.0 2006-03-07 initial version.
 */
package com.mindprod.common18;

import javax.swing.JApplet;
import javax.swing.JFrame;
import javax.swing.SwingUtilities;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;

/**
 * Converts a JApplet into an Application.
 *
 * @author Roedy Green, Canadian Mind Products
 * @version 1.0 2006-03-07
 * @since 2006-03-07
 */
public final class HybridJ
    {
    /**
     * return code to use when Applet run as an Application
     */
    private static int retCode = 0;

    /**
     * Fire up the JApplet as an application
     *
     * @param title             title for frame usually TITLE_STRING+ " " + VERSION_STRING
     * @param applicationWidth  width of frame, usually APPLET_WIDTH
     * @param applicationHeight height of frame body,  usually APPLET_HEIGHT
     */
    public static void fireup( final JApplet applet,
                               final String title,
                               final int applicationWidth,
                               final int applicationHeight )
        {
        // fire up JApplet on the Swing Thread
        SwingUtilities.invokeLater( new Runnable()
            {
            /**
             * do all swing work on the swing thread.
             */
            public void run()
                {
                JFrame.setDefaultLookAndFeelDecorated( true );
                final JFrame frame = new JFrame( title );
                frame.setResizable( true );
                frame.setUndecorated( false );
                frame.setDefaultCloseOperation( JFrame.DO_NOTHING_ON_CLOSE );
                // allow some extra room for the frame title bar.
                frame.setSize( applicationWidth + 22, applicationHeight + 32 );
                frame.addWindowListener( new WindowAdapter()
                    {
                    /**
                     * Handle request to shutdown.
                     * @param e event giving details of closing.
                     */
                    public void windowClosing( WindowEvent e )
                        {
                        applet.stop();
                        applet.destroy();
                        System.exit( retCode );
                        } // end WindowClosing
                    } // end anonymous class
                );// end addWindowListener line
                frame.getContentPane().add( applet );
                applet.init();
                // yes frame, not contentpane.
                frame.validate();
                frame.setVisible( true );
                applet.start();
                } // end run
            } // end runnable
        );
        }

    /**
     * set return code to use when Applet run as an Application
     *
     * @param retCode code for System.exit
     */
    public static void setRetCode( final int retCode )
        {
        HybridJ.retCode = retCode;
        }
    }
